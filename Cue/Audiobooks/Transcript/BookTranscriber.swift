import AVFoundation
import Defaults
import Foundation
import MusicSearchKit
import Observation
import OSLog
import SonosKit

/// A book's words on screen as it plays (Cue Super): the file playing,
/// transcribed on the device (`BookTranscriptionEngine`, iOS 26 and later).
/// Nothing leaves the device.
///
/// The file is read ahead of the listener, faster than it plays and five
/// minutes ahead, so the transcript is there before the words are said and
/// follows them like timed lyrics, playing or paused, on this device or a
/// speaker: a downloaded file from the device, a streamed MP3 from the
/// server in pieces (`BookTranscriptionEngine.read(remote:)`). A streamed
/// file that can't be read in pieces (an M4B) is heard as it plays instead,
/// through the tap Smart Resume listens with (`BookAudioListener`), on this
/// device only.
/// Whatever is heard is kept by the file (`BookTranscriptStore`), so a
/// stretch is transcribed once.
///
/// It only runs while the transcript shows: the view `activate()`s and
/// `deactivate()`s it. The language is kept per book, with the last pick
/// the guess for a book not transcribed before.
@MainActor
@Observable
final class BookTranscriber {
    static let shared = BookTranscriber()

    enum State: Equatable {
        case idle
        /// This OS or device has no on-device transcriber.
        case unsupported
        /// Cue Super unlocks it.
        case needsSuper
        /// Nothing to transcribe; the reason says why.
        case unavailable(String)
        /// Heard only as it plays, and it's paused.
        case waitingForPlay
        case preparing
        case downloadingModel(Double)
        case transcribing
        case failed(String)
    }

    private(set) var state: State = .idle
    /// The file playing's transcript, as far as it's been heard.
    private(set) var transcript = BookTranscript() {
        didSet { revision += 1 }
    }
    /// Counts changes to `transcript`, for the view to tell a new one from
    /// the last without comparing hours of lines.
    private(set) var revision = 0
    /// While a streamed file is heard: the words being said, a guess the
    /// next result replaces.
    private(set) var volatileText: String?
    /// The file the transcript is of.
    private(set) var fileKey: String?
    /// The file is heard as it plays, not read ahead.
    private(set) var isLive = false
    private(set) var locale: Locale?
    private(set) var supportedLocales: [Locale] = []

    static var isSupported: Bool { LiveTranscriptionService.isSupported }

    private static let anyBookKey = "*"
    /// A move of the playhead this far from where playing would have taken
    /// it is a seek: a live run starts again from there.
    private static let seekTolerance: TimeInterval = 4

    /// Files whose server won't let them be read in pieces: heard live.
    private var notReadable: Set<String> = []
    private var activeCount = 0
    private var monitor: Task<Void, Never>?
    private var run: Task<Void, Never>?
    /// What the running transcription is of.
    private var running: Running?
    private var pace: BookTranscriptPace?
    private var lastPlayhead: (time: TimeInterval, at: Date)?

    private struct Running: Equatable {
        let fileKey: String
        let locale: String
        let isLive: Bool
        let start: TimeInterval
    }

    /// Where a file read ahead comes from.
    private enum Source {
        case file(URL)
        case server(URL, duration: TimeInterval)
    }

    private init() {}

    func activate() {
        activeCount += 1
        guard monitor == nil else { return }
        if supportedLocales.isEmpty {
            Task { await loadSupportedLocales() }
        }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func deactivate() {
        activeCount = max(0, activeCount - 1)
        guard activeCount == 0 else { return }
        monitor?.cancel()
        monitor = nil
        stopRun()
        state = .idle
    }

    /// Picks the book's language, kept for it and as the guess for the next.
    func setLocale(_ locale: Locale) {
        guard let book = AudiobookPlayer.shared.current?.book else { return }
        var saved = savedLocales
        saved[Self.bookKey(book)] = locale.identifier
        saved[Self.anyBookKey] = locale.identifier
        UserDefaults.standard.set(saved, forKey: AppStorageKeys.bookTranscriptLocales)
        self.locale = locale
        stopRun()
        tick()
    }

    // MARK: - Following the player

    private func tick() {
        guard FeatureGate.shared.isAvailable(.bookTranscript) else {
            stopRun()
            state = .needsSuper
            return
        }
        let controller = PlaybackRoute.shared.presented
        let player = AudiobookPlayer.shared
        guard let book = player.current, player.isPlayingBook(on: controller),
              let part = book.partIndex(of: controller.nowPlayingDisplay) else {
            stopRun()
            state = .unavailable(String(localized: "Play a book to read along."))
            return
        }
        let file = book.parts[part]
        let key = BookTranscriptStore.key(for: PlayableContentKey(service: file.content.service.sonosRawValue, id: file.content.id))
        if key != fileKey {
            stopRun()
            fileKey = key
            transcript = BookTranscriptStore.shared.transcript(for: key)
            volatileText = nil
            lastPlayhead = nil
            Logger.bookTranscript.notice("following \(key, privacy: .public), \(self.transcript.lines.count) lines kept")
        }
        // What's kept still reads where nothing new can be transcribed.
        guard Self.isSupported else {
            state = .unsupported
            return
        }
        let locale = preferredLocale(for: book.book)
        self.locale = locale
        let playhead = controller.position()
        pace?.playhead = playhead

        let duration = book.timeline.partDurations.indices.contains(part) ? book.timeline.partDurations[part] : 0
        if let url = DownloadManager.shared.localURL(for: file) {
            followAhead(.file(url), key: key, locale: locale, playhead: playhead)
        } else if !notReadable.contains(key), let url = LocalPlaybackService.shared.bookFileURL(for: file), !url.isFileURL {
            followAhead(.server(url, duration: duration), key: key, locale: locale, playhead: playhead)
        } else if controller.group == nil, let item = LocalPlaybackService.shared.currentStreamItem {
            followLive(item, key: key, locale: locale, playhead: playhead, isPlaying: controller.isPlaying)
        } else {
            stopRun()
            state = .unavailable(String(localized: "Download this book to read along while it plays on a speaker."))
        }
    }

    /// A file read ahead from just before the listener, from the first
    /// stretch not transcribed yet. A run carries on while the listener
    /// stays within what it's reading; a jump outside starts one from there.
    private func followAhead(_ source: Source, key: String, locale: Locale, playhead: TimeInterval) {
        let from = transcript.firstUncovered(from: max(0, playhead - 10))
        if let running, running.fileKey == key, running.locale == locale.identifier, !running.isLive, let pace {
            let fed = pace.fed
            if from >= running.start - 1, from <= fed + 60 { return }
        }
        // All of what's ahead is read: nothing to run until the listener
        // gets near its end.
        if from > playhead + BookTranscriptPace.lookahead - 30 {
            if running == nil, state != .transcribing { state = .transcribing }
            return
        }
        guard #available(iOS 26.0, visionOS 26.0, *) else { return }
        stopRun()
        let pace = BookTranscriptPace(start: from)
        pace.playhead = playhead
        self.pace = pace
        isLive = false
        let running = Running(fileKey: key, locale: locale.identifier, isLive: false, start: from)
        Logger.bookTranscript.notice("reading \(key, privacy: .public) ahead from \(Int(from)) s, \(locale.identifier, privacy: .public)")
        start({ [weak self] in
            switch source {
            case .file(let url):
                if let audio = BookTranscriptionEngine.read(url, from: from, pace: pace) { return audio }
                self?.state = .failed(String(localized: "This file can't be read for a transcript."))
                return nil
            case .server(let url, let duration):
                if let audio = await BookTranscriptionEngine.read(remote: url, duration: duration, from: from, pace: pace) { return audio }
                // Heard as it plays from here on.
                self?.notReadable.insert(key)
                if self?.running == running { self?.running = nil }
                return nil
            }
        }, running: running, locale: locale)
    }

    /// A streamed file on this device: heard through the tap as it plays,
    /// again from the new place after a seek.
    private func followLive(_ item: AVPlayerItem, key: String, locale: Locale, playhead: TimeInterval, isPlaying: Bool) {
        defer { lastPlayhead = (playhead, .now) }
        if let running, running.fileKey == key, running.locale == locale.identifier, running.isLive {
            if !isPlaying, transcript.lines.isEmpty, volatileText == nil { state = .waitingForPlay }
            guard let last = lastPlayhead else { return }
            let expected = last.time + (isPlaying ? Date.now.timeIntervalSince(last.at) * Double(AudiobookPlayer.shared.rate) : 0)
            if abs(playhead - expected) < Self.seekTolerance { return }
            Logger.bookTranscript.notice("seek to \(Int(playhead)) s; hearing again from there")
        }
        guard #available(iOS 26.0, visionOS 26.0, *) else { return }
        stopRun()
        guard let audio = BookAudioListener.shared.transcribe(item) else {
            state = .preparing
            return
        }
        Logger.bookTranscript.notice("hearing \(key, privacy: .public) live from \(Int(playhead)) s, \(locale.identifier, privacy: .public)")
        isLive = true
        start({ audio }, running: Running(fileKey: key, locale: locale.identifier, isLive: true, start: playhead), locale: locale)
        if !isPlaying, transcript.lines.isEmpty { state = .waitingForPlay }
    }

    /// Opens the audio and transcribes it. `open` gives nil when the source
    /// can't be read; the next tick picks another.
    @available(iOS 26.0, visionOS 26.0, *)
    private func start(_ open: @escaping @MainActor () async -> AsyncStream<BookAudioChunk>?, running: Running, locale: Locale) {
        self.running = running
        if state != .transcribing { state = .preparing }
        let key = running.fileKey
        run = Task { [weak self] in
            guard let audio = await open(), !Task.isCancelled else { return }
            do {
                try await BookTranscriptionEngine.run(
                    locale: locale,
                    audio: audio,
                    live: running.isLive,
                    onStatus: { status in
                        guard let self, self.running == running else { return }
                        switch status {
                        case .downloading(let fraction): self.state = .downloadingModel(fraction)
                        case .transcribing: self.state = .transcribing
                        }
                    },
                    onLines: { lines, through in
                        self?.add(lines, through: through, running: running, key: key)
                    },
                    onProgress: { through in
                        guard let self, self.running == running else { return }
                        self.pace?.heardThrough = through
                    },
                    onVolatile: { text in
                        guard let self, self.running == running else { return }
                        self.volatileText = text
                    }
                )
                // Read to the file's end.
                if let self, self.running == running { self.running = nil }
            } catch {
                guard let self, self.running == running else { return }
                Logger.bookTranscript.error("transcription failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed(error.localizedDescription)
                self.running = nil
            }
        }
    }

    private func add(_ lines: [BookTranscript.Line], through: TimeInterval, running: Running, key: String) {
        let start = lines.first?.start ?? through
        let updated = BookTranscriptStore.shared.update(key) { transcript in
            transcript.insert(lines)
            transcript.cover(min(running.start, start)...max(through, start))
        }
        if fileKey == key {
            transcript = updated
        }
        if self.running == running {
            pace?.heardThrough = through
        }
    }

    private func stopRun() {
        run?.cancel()
        run = nil
        running = nil
        pace = nil
        volatileText = nil
        BookAudioListener.shared.stopTranscribing()
    }

    // MARK: - Language

    private var savedLocales: [String: String] {
        UserDefaults.standard.dictionary(forKey: AppStorageKeys.bookTranscriptLocales) as? [String: String] ?? [:]
    }

    private static func bookKey(_ book: PlayableContent) -> String {
        "\(book.content.service.sonosRawValue).\(book.content.id)"
    }

    /// The book's language, else the last one picked, else the device's.
    private func preferredLocale(for book: PlayableContent) -> Locale {
        let saved = savedLocales
        let identifier = saved[Self.bookKey(book)] ?? saved[Self.anyBookKey]
        return identifier.map(Locale.init(identifier:)) ?? Locale.current
    }

    private func loadSupportedLocales() async {
        guard #available(iOS 26.0, visionOS 26.0, *) else { return }
        let locales = await TranscriptionEngine.supportedLocales()
        supportedLocales = locales.sorted { LiveTranscriptionService.displayName(for: $0) < LiveTranscriptionService.displayName(for: $1) }
    }
}
