import AVFoundation
import Defaults
import Foundation
import Observation
import SonosKit

/// Live Transcription: what's being said or sung in the audio this device is
/// playing, written out as it plays, by an on-device model
/// (`TranscriptionEngine`, iOS 26 and later).
///
/// It hears the player itself, not the room — a tap on `LocalPlaybackService`'s
/// stream player (`TranscriptionAudioTap`) — so it works with headphones in and
/// the volume down, and only for what that player plays: TuneIn, Plex,
/// Subsonic and Files. Apple Music's audio never passes through the app, and
/// a speaker's never reaches the device at all; for those the panel says why
/// there's nothing to show.
///
/// It only runs while the player shows it: the panel `activate()`s on appear
/// and `deactivate()`s on disappear, which also takes the taps off, so
/// playback with the panel closed is exactly what it was before this existed.
/// Whether the panel shows is `isEnabled`, kept across launches.
///
/// The language is per station — a French station stays French — and for
/// anything that isn't a station, the last language picked. A language's
/// model downloads the first time it's chosen.
@MainActor
@Observable
final class LiveTranscriptionService {
    static let shared = LiveTranscriptionService()

    /// The `liveTranscriptionLocales` key for everything that isn't a station.
    static let anyContentKey = "*"

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    enum State: Equatable {
        /// Not running: the panel is closed.
        case idle
        /// This OS or device has no on-device transcriber.
        case unsupported
        /// What's playing can't be heard by the app; the reason says why.
        case unavailable(String)
        case downloading(Double)
        case listening
        case failed(String)
    }

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: AppStorageKeys.liveTranscriptionEnabled) {
        didSet { UserDefaults.standard.set(isEnabled, forKey: AppStorageKeys.liveTranscriptionEnabled) }
    }

    private(set) var state: State = .idle
    /// Finished lines, oldest first.
    private(set) var lines: [Line] = []
    /// The line still being heard — replaced as the model changes its mind,
    /// then moved into `lines` once it's final.
    private(set) var volatileText = ""
    /// The language transcribing now, or about to.
    private(set) var locale: Locale?
    /// Every language the transcriber knows, by display name.
    private(set) var supportedLocales: [Locale] = []

    /// Whether this device can transcribe at all — iOS 26 or later, with the
    /// model supported on the hardware.
    static var isSupported: Bool {
        if #available(iOS 26.0, visionOS 26.0, *) {
            return TranscriptionEngine.isAvailable
        }
        return false
    }

    private var playback: LocalPlaybackService { .shared }

    @ObservationIgnored private var isActive = false
    private let feed = AudioFeed()
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    /// Bumped per engine start, so a cancelled run's late callbacks can't
    /// write over the current one's state.
    @ObservationIgnored private var generation = 0
    /// What the running engine is transcribing, and in which language.
    @ObservationIgnored private var runningContentID: String?
    @ObservationIgnored private var runningLocale: Locale?
    /// Items with a tap on, weakly — the queue player owns them.
    @ObservationIgnored private var tappedItems: [WeakItem] = []
    /// A cap on the transcript kept on screen.
    private let maxLines = 200

    private init() {}

    // MARK: - Panel lifecycle

    func activate() {
        guard !isActive else { return }
        isActive = true
        if supportedLocales.isEmpty {
            Task { await loadSupportedLocales() }
        }
        for item in playback.streamItems {
            tap(item)
        }
        observePlayback()
        refresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        stopEngine()
        for item in tappedItems.compactMap(\.item) {
            TranscriptionAudioTap.remove(from: item)
        }
        tappedItems = []
        state = .idle
    }

    /// `LocalPlaybackService` armed a new player item. Tapped while the panel
    /// is open; left alone otherwise.
    func playerItemArmed(_ item: AVPlayerItem) {
        guard isActive else { return }
        tap(item)
    }

    /// Transcribes in `locale` from now on, and remembers it for what's
    /// playing — the station, or everything that isn't one.
    func setLocale(_ locale: Locale) {
        var saved = savedLocales
        saved[localeKey(for: playback.nowPlaying)] = locale.identifier
        // A station's pick is also the best guess for anything new.
        saved[Self.anyContentKey] = locale.identifier
        UserDefaults.standard.set(saved, forKey: AppStorageKeys.liveTranscriptionLocales)
        refresh()
    }

    // MARK: - Following playback

    /// Re-reads what's playing whenever it changes, for as long as the panel
    /// is open.
    private func observePlayback() {
        guard isActive else { return }
        withObservationTracking {
            _ = playback.nowPlaying?.content.id
            _ = playback.isPlayingLocalStream
        } onChange: {
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.observePlayback()
            }
        }
    }

    /// Brings the engine in line with what's playing: stopped when there's
    /// nothing it can hear, restarted for a new song or station or language,
    /// left running otherwise.
    private func refresh() {
        guard isActive else { return }
        guard Self.isSupported else {
            stopEngine()
            state = .unsupported
            return
        }
        guard let item = playback.nowPlaying else {
            stopEngine()
            clearTranscript()
            state = .unavailable("Play something on this device to see what's being said.")
            return
        }
        guard playback.isPlayingLocalStream else {
            stopEngine()
            clearTranscript()
            state = .unavailable(item.content.service == .apple
                ? "Apple Music plays inside Apple's own player, so its audio can't be transcribed. Radio, Plex, Subsonic and Files can."
                : "Nothing this device can hear is playing.")
            return
        }

        let locale = preferredLocale(for: item)
        self.locale = locale
        if runningContentID != item.content.id {
            clearTranscript()
        }
        guard engineTask == nil || runningContentID != item.content.id || runningLocale != locale else { return }
        startEngine(contentID: item.content.id, locale: locale)
    }

    private func startEngine(contentID: String, locale: Locale) {
        guard #available(iOS 26.0, visionOS 26.0, *) else { return }
        stopEngine()
        generation += 1
        let generation = generation
        runningContentID = contentID
        runningLocale = locale
        state = .listening

        let audio = feed.open()
        engineTask = Task { [weak self] in
            do {
                try await TranscriptionEngine.run(locale: locale, audio: audio) { status in
                    guard let self, self.generation == generation else { return }
                    switch status {
                    case .downloading(let fraction): self.state = .downloading(fraction)
                    case .listening: self.state = .listening
                    }
                } onResult: { text, isFinal in
                    guard let self, self.generation == generation else { return }
                    self.receive(text, isFinal: isFinal)
                }
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    private func stopEngine() {
        engineTask?.cancel()
        engineTask = nil
        feed.close()
        runningContentID = nil
        runningLocale = nil
    }

    private func receive(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFinal else {
            volatileText = trimmed
            return
        }
        volatileText = ""
        guard !trimmed.isEmpty else { return }
        lines.append(Line(text: trimmed))
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    private func clearTranscript() {
        lines = []
        volatileText = ""
    }

    private func tap(_ item: AVPlayerItem) {
        guard Self.isSupported, !tappedItems.contains(where: { $0.item === item }) else { return }
        tappedItems.removeAll { $0.item == nil }
        tappedItems.append(WeakItem(item: item))
        let feed = feed
        Task {
            let installed = await TranscriptionAudioTap.install(on: item) { buffer in
                feed.send(buffer)
            }
            // Closed while the item was still getting ready.
            if installed, !isActive || !tappedItems.contains(where: { $0.item === item }) {
                TranscriptionAudioTap.remove(from: item)
            }
        }
    }

    // MARK: - Languages

    private var savedLocales: [String: String] {
        UserDefaults.standard.dictionary(forKey: AppStorageKeys.liveTranscriptionLocales) as? [String: String] ?? [:]
    }

    private func localeKey(for item: PlayableContent?) -> String {
        guard let item, playback.isPlayingStation else { return Self.anyContentKey }
        return item.content.id
    }

    /// The station's language, else the last one picked, else the device's.
    private func preferredLocale(for item: PlayableContent) -> Locale {
        let saved = savedLocales
        let identifier = saved[localeKey(for: item)] ?? saved[Self.anyContentKey]
        return identifier.map(Locale.init(identifier:)) ?? Locale.current
    }

    private func loadSupportedLocales() async {
        guard #available(iOS 26.0, visionOS 26.0, *) else { return }
        let locales = await TranscriptionEngine.supportedLocales()
        supportedLocales = locales.sorted { Self.displayName(for: $0) < Self.displayName(for: $1) }
    }

    /// "English (United States)", in the device's language.
    static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

/// Where tapped audio goes: the running engine's stream, or nowhere between
/// runs. Called from the render thread, hence the lock.
private final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    /// A fresh stream for a new engine run, ending the last one's.
    func open() -> AsyncStream<AVAudioPCMBuffer> {
        // Newest first if the model falls behind: live captions that lag
        // further and further are worse than a skipped phrase.
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self, bufferingPolicy: .bufferingNewest(512))
        let previous = lock.withLock {
            let previous = self.continuation
            self.continuation = continuation
            return previous
        }
        previous?.finish()
        return stream
    }

    func close() {
        let previous = lock.withLock {
            let previous = continuation
            continuation = nil
            return previous
        }
        previous?.finish()
    }

    func send(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { continuation }?.yield(buffer)
    }
}

private struct WeakItem {
    weak var item: AVPlayerItem?
}
