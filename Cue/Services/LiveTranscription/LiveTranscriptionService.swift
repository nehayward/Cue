import AVFoundation
import DanceLogger
import Defaults
import Foundation
import Observation
import SonosKit

/// Live Transcription: what's being said on the radio station playing,
/// written out as it airs, by an on-device model (`TranscriptionEngine`,
/// iOS 26 and later). Nothing leaves the device.
///
/// It follows the station wherever the player's route points, and hears it
/// the same way either way: the station is a public stream, so the device
/// opens it a second time and decodes it itself (`LiveStreamDecoder`) — the
/// URL `LocalPlaybackService` is playing, or the one a speaker is
/// (`SonosService.radioStreamURL(for:)`). No microphone, nothing audible,
/// and it works with headphones in and the volume down. (Tapping `AVPlayer`
/// can't do this: a live Icecast stream has no asset track to tap.) The
/// player buffers on its own clock, so the words can run a few seconds ahead
/// of or behind what's heard. It stops while a speaker is paused.
///
/// Apple Music stations play inside Apple's own player, and Sonos Radio,
/// HLS and Ogg stations and other speaker-only services have no stream the
/// device can decode; for those the panel says why there's nothing to show.
///
/// It only runs while the player shows it: the panel `activate()`s on appear
/// and `deactivate()`s on disappear, which closes the stream, so nothing
/// runs while it's closed.
/// Whether the panel shows is `isEnabled`, kept across launches.
///
/// The language is remembered per station — a French station stays French —
/// with the last pick as the guess for a station not heard before. A
/// language's model downloads the first time it's chosen.
@MainActor
@Observable
final class LiveTranscriptionService {
    static let shared = LiveTranscriptionService()

    /// The `liveTranscriptionLocales` key for a station with no pick yet.
    static let anyStationKey = "*"

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    enum State: Equatable {
        /// Not running: the panel is closed.
        case idle
        /// This OS or device has no on-device transcriber.
        case unsupported
        /// What's playing can't be transcribed; the reason says why.
        case unavailable(String)
        /// The speaker is paused; the transcript so far stays up.
        case paused
        /// Opening the station's stream.
        case connecting
        case downloading(Double)
        case listening
        case failed(String)
    }

    /// Where the station is heard from.
    private enum Source: Equatable {
        /// Playing on this device.
        case device(stationID: String)
        /// Playing on a speaker.
        case speaker(stationID: String)

        var stationID: String {
            switch self {
            case .device(let id), .speaker(let id): id
            }
        }
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

    /// Whether a station is what the player is showing — on this device or
    /// the speaker the route points at. The player's button shows only then.
    static var isStationPlaying: Bool {
        if let group = PlaybackRoute.shared.group {
            return group.coordinatorRoom.isPlayingRadio
        }
        return LocalPlaybackService.shared.isPlayingStation
    }

    private var playback: LocalPlaybackService { .shared }
    private var route: PlaybackRoute { .shared }

    @ObservationIgnored private var isActive = false
    @ObservationIgnored private let feed = AudioFeed()
    /// The station whose stream couldn't be opened, not retried until
    /// something changes.
    @ObservationIgnored private var failedSource: Source?
    /// Reading and decoding the station's stream.
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    /// Bumped per engine start, so a cancelled run's late callbacks can't
    /// write over the current one's state.
    @ObservationIgnored private var generation = 0
    /// What the running engine is transcribing, and in which language.
    @ObservationIgnored private var runningSource: Source?
    @ObservationIgnored private var runningLocale: Locale?
    /// The station the transcript on screen belongs to.
    @ObservationIgnored private var transcriptStationID: String?
    /// A cap on the transcript kept on screen.
    @ObservationIgnored private let maxLines = 200

    private init() {}

    // MARK: - Panel lifecycle

    func activate() {
        guard !isActive else { return }
        isActive = true
        if supportedLocales.isEmpty {
            Task { await loadSupportedLocales() }
        }
        observePlayback()
        refresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        failedSource = nil
        stop()
        state = .idle
    }

    /// Transcribes in `locale` from now on, and remembers it for the station
    /// playing — and as the first guess for stations not heard before.
    func setLocale(_ locale: Locale) {
        var saved = savedLocales
        if let stationID = currentSource()?.stationID {
            saved[stationID] = locale.identifier
        }
        saved[Self.anyStationKey] = locale.identifier
        UserDefaults.standard.set(saved, forKey: AppStorageKeys.liveTranscriptionLocales)
        failedSource = nil
        refresh()
    }

    // MARK: - Following playback

    /// Re-reads what's playing whenever it changes, for as long as the panel
    /// is open: the route, the device's station, the speaker's station and
    /// whether it's playing.
    private func observePlayback() {
        guard isActive else { return }
        withObservationTracking {
            _ = currentSource()
            _ = isSourcePlaying
        } onChange: {
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.observePlayback()
            }
        }
    }

    /// The station playing where the route points, if it's one Cue can hear.
    private func currentSource() -> Source? {
        if let group = route.group {
            let room = group.coordinatorRoom
            guard room.isPlayingRadio else { return nil }
            // TuneIn's id where the speaker gives one, so a station keeps its
            // language between this device and a speaker; the station's name
            // otherwise.
            guard let stationID = room.track.metadata?.stationID ?? room.radioStation ?? room.track.trackID.nilIfEmpty else { return nil }
            return .speaker(stationID: stationID)
        }
        guard playback.isPlayingStation, playback.isPlayingLocalStream,
              let item = playback.nowPlaying, item.content.service == .tuneIn else { return nil }
        return .device(stationID: item.content.id)
    }

    /// Brings the engine in line with what's playing: stopped when there's
    /// no station it can hear, restarted for a new station or language, left
    /// running otherwise.
    private func refresh() {
        guard isActive else { return }
        guard Self.isSupported else {
            stop()
            state = .unsupported
            return
        }
        guard let source = currentSource() else {
            stop()
            clearTranscript()
            state = .unavailable(unavailableReason)
            return
        }
        // A station that failed stays failed until something changes —
        // retrying on every metadata tick would only flash the error.
        if source == failedSource { return }
        if !isSourcePlaying {
            // Live radio doesn't wait: listening on while it's paused would
            // transcribe what was never played.
            stop()
            state = .paused
            return
        }

        let locale = preferredLocale(for: source.stationID)
        self.locale = locale
        if transcriptStationID != source.stationID {
            clearTranscript()
            transcriptStationID = source.stationID
        }
        guard engineTask == nil || runningSource != source || runningLocale != locale else { return }
        start(source, locale: locale)
    }

    /// Whether the station is playing, rather than paused, where it plays.
    private var isSourcePlaying: Bool {
        if let group = route.group {
            return group.coordinatorRoom.isPlaying
        }
        return playback.isPlaying
    }

    /// Why nothing can be shown for what's playing.
    private var unavailableReason: String {
        if let group = route.group {
            let room = group.coordinatorRoom
            return "Play a radio station on \(room.name) to see what's being said."
        }
        guard let item = playback.nowPlaying, playback.isPlayingStation else {
            return "Play a radio station to see what's being said."
        }
        if item.content.service == .apple {
            return "Apple Music radio plays inside Apple's own player, so it can't be transcribed. TuneIn stations can."
        }
        return "This station can't be transcribed."
    }

    private func start(_ source: Source, locale: Locale) {
        guard #available(iOS 26.0, visionOS 26.0, *) else { return }
        // Both halves restart together — a language change reconnects to
        // the station too — so a stream can never outlive its run.
        stop()
        generation += 1
        let generation = generation
        runningSource = source
        runningLocale = locale

        // The engine's stream is opened before any audio is, so the first
        // words aren't dropped on the floor.
        let audio = feed.open()
        listen(to: source, generation: generation)
        state = .connecting

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
                DanceLog.liveTranscription.error("Transcriber failed: \(error.localizedDescription, privacy: .public)")
                self?.listenFailed(error.localizedDescription, generation: generation)
            }
        }
    }

    /// Opens the station's stream here and decodes it into the feed — the
    /// URL the player is playing, or the one the speaker is.
    private func listen(to source: Source, generation: Int) {
        let group = route.group
        let feed = feed
        listenTask = Task { [weak self] in
            var url: URL?
            switch source {
            case .device:
                url = await LocalPlaybackService.shared.currentStationStreamURL()
            case .speaker:
                if let group {
                    url = await SonosService.shared.radioStreamURL(for: group)
                }
            }
            guard let url else {
                self?.listenFailed("This station has no stream Cue can open on this device — Sonos Radio and some speaker-only stations can't be transcribed.", generation: generation)
                return
            }
            do {
                // Off the main actor: parsing and decoding every packet of
                // the stream is steady work.
                try await Task.detached(priority: .userInitiated) {
                    try await LiveStreamDecoder.run(url) { buffer in
                        feed.send(buffer)
                    }
                }.valueCancellingOnCancel()
                self?.listenFailed("The station's stream ended.", generation: generation)
            } catch is CancellationError {
            } catch {
                DanceLog.liveTranscription.error("Stream failed: \(error.localizedDescription, privacy: .public)")
                self?.listenFailed(error.localizedDescription, generation: generation)
            }
        }
    }

    private func listenFailed(_ reason: String, generation: Int) {
        guard self.generation == generation, !Task.isCancelled else { return }
        let source = runningSource
        stop()
        failedSource = source
        state = .failed(reason)
    }

    private func stop() {
        stopEngine()
        stopListening()
        runningSource = nil
    }

    private func stopEngine() {
        engineTask?.cancel()
        engineTask = nil
        feed.close()
        runningLocale = nil
    }

    private func stopListening() {
        listenTask?.cancel()
        listenTask = nil
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
        transcriptStationID = nil
    }

    // MARK: - Languages

    private var savedLocales: [String: String] {
        UserDefaults.standard.dictionary(forKey: AppStorageKeys.liveTranscriptionLocales) as? [String: String] ?? [:]
    }

    /// The station's language, else the last one picked, else the device's.
    private func preferredLocale(for stationID: String) -> Locale {
        let saved = savedLocales
        let identifier = saved[stationID] ?? saved[Self.anyStationKey]
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

/// Where decoded audio goes: the running engine's stream, or nowhere between
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

private extension Task where Failure == Error {
    /// The task's value, cancelling the task if the one awaiting it is
    /// cancelled — a detached task doesn't inherit cancellation.
    func valueCancellingOnCancel() async throws -> Success {
        try await withTaskCancellationHandler {
            try await value
        } onCancel: {
            cancel()
        }
    }
}

private extension Room {
    /// A station is on: the speaker named one, or said the track is radio.
    var isPlayingRadio: Bool {
        radioStation != nil || track.metadata?.contentType == .radio
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
