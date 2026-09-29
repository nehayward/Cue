import AVFoundation
import Defaults
import Foundation
import Observation
import SonosKit

/// Live Transcription: what's being said on the radio station playing,
/// written out as it airs, by an on-device model (`TranscriptionEngine`,
/// iOS 26 and later). Nothing leaves the device.
///
/// It follows a TuneIn station wherever the player's route points:
/// - **On this device** it hears the player itself — a tap on
///   `LocalPlaybackService`'s stream item (`TranscriptionAudioTap`) — so it
///   works with headphones in and the volume down, and costs no extra data.
/// - **On a speaker** the audio never reaches the device, but the station is
///   a public stream: `RadioStreamListener` opens the same station here,
///   silently, and taps that. The speaker buffers on its own clock, so the
///   words can run a few seconds ahead of or behind the room. It stops while
///   the speaker is paused.
///
/// Apple Music stations play inside Apple's own player, and Sonos Radio and
/// other speaker-only stations have no stream the device can open; for those
/// the panel says why there's nothing to show.
///
/// It only runs while the player shows it: the panel `activate()`s on appear
/// and `deactivate()`s on disappear, which takes the taps off and closes the
/// silent stream, so nothing about playback changes while it's closed.
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
        /// Playing on this device: tap the player's own item.
        case device(stationID: String)
        /// Playing on a speaker: open the stream here and tap that.
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
    @ObservationIgnored private let listener = RadioStreamListener()
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    /// Bumped per engine start, so a cancelled run's late callbacks can't
    /// write over the current one's state.
    @ObservationIgnored private var generation = 0
    /// What the running engine is transcribing, and in which language.
    @ObservationIgnored private var runningSource: Source?
    @ObservationIgnored private var runningLocale: Locale?
    /// The station the transcript on screen belongs to.
    @ObservationIgnored private var transcriptStationID: String?
    /// Player items with a tap on, weakly — the queue player owns them.
    @ObservationIgnored private var tappedItems: [WeakItem] = []
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
        stop()
        state = .idle
    }

    /// `LocalPlaybackService` armed a new player item. Tapped while a station
    /// on this device is being transcribed; left alone otherwise.
    func playerItemArmed(_ item: AVPlayerItem) {
        guard isActive, case .device = runningSource else { return }
        tap(item)
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
            _ = route.group?.coordinatorRoom.isPlaying
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
            let track = group.coordinatorRoom.track
            guard track.musicService == .tuneIn, let stationID = track.metadata?.stationID else { return nil }
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
        if case .speaker = source, route.group?.coordinatorRoom.isPlaying != true {
            // Live radio doesn't wait: listening on while the room is quiet
            // would transcribe what the room never played.
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

    /// Why nothing can be shown for what's playing.
    private var unavailableReason: String {
        if let group = route.group {
            let room = group.coordinatorRoom
            guard room.isPlayingRadio else {
                return "Play a radio station on \(room.name) to see what's being said."
            }
            return "Only TuneIn stations can be transcribed while they play on a speaker — this one has no stream Cue can open."
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
        let sourceChanged = runningSource != source
        stopEngine()
        if sourceChanged {
            stopListening()
        }
        generation += 1
        let generation = generation
        runningSource = source
        runningLocale = locale

        // The engine's stream is opened before any audio is, so the first
        // words aren't dropped on the floor.
        let audio = feed.open()
        if sourceChanged {
            listen(to: source, generation: generation)
        }
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
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    /// Starts audio flowing into the feed from `source`.
    private func listen(to source: Source, generation: Int) {
        switch source {
        case .device:
            for item in playback.streamItems {
                tap(item)
            }
        case .speaker(let stationID):
            let feed = feed
            Task {
                let opened = await listener.open(stationID: stationID) { buffer in
                    feed.send(buffer)
                }
                guard !opened, self.generation == generation else { return }
                stop()
                state = .failed("Couldn't open this station's stream on this device.")
            }
        }
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
        listener.close()
        for item in tappedItems.compactMap(\.item) {
            TranscriptionAudioTap.remove(from: item)
        }
        tappedItems = []
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

    private func tap(_ item: AVPlayerItem) {
        guard !tappedItems.contains(where: { $0.item === item }) else { return }
        tappedItems.removeAll { $0.item == nil }
        tappedItems.append(WeakItem(item: item))
        let feed = feed
        Task {
            let installed = await TranscriptionAudioTap.install(on: item) { buffer in
                feed.send(buffer)
            }
            // Stopped while the item was still getting ready.
            if installed, !tappedItems.contains(where: { $0.item === item }) {
                TranscriptionAudioTap.remove(from: item)
            }
        }
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

/// Opens a station's stream on this device with the sound off, for hearing a
/// station that's playing on a speaker. Its own `AVPlayer`, kept apart from
/// `LocalPlaybackService`'s: this one is never heard, never takes the Lock
/// Screen and never goes to AirPlay.
@MainActor
private final class RadioStreamListener {
    private var player: AVPlayer?
    /// Bumped per open, so an open still resolving when it's closed or
    /// replaced doesn't start a player behind the newer one.
    private var token = 0

    /// Starts the station's stream silently and taps it. Returns whether
    /// audio is now flowing to `onBuffer`.
    func open(stationID: String, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async -> Bool {
        close()
        token += 1
        let token = token
        // The same non-HLS pick the device player makes: an HLS stream has
        // no track to tap.
        guard let url = await MusicSearchService.shared.tuneInStreamURL(id: stationID),
              self.token == token else { return false }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // Silent, not muted: the tap sits before the volume stage, so it
        // still hears the stream at full level.
        player.volume = 0
        player.allowsExternalPlayback = false
        self.player = player
        player.play()

        let installed = await TranscriptionAudioTap.install(on: item, onBuffer: onBuffer)
        guard self.token == token else { return false }
        if !installed { close() }
        return installed
    }

    func close() {
        token += 1
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
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

private extension Room {
    /// A station is on: the speaker named one, or said the track is radio.
    var isPlayingRadio: Bool {
        radioStation != nil || track.metadata?.contentType == .radio
    }
}
