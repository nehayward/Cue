#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import Defaults
import MediaPlayer
import Nuke
import Observation
import SonosKit
import UIKit

/// Mirrors a Sonos group onto the system Now Playing card — Lock Screen,
/// Control Center, CarPlay, AirPods stem presses, the Watch's Now Playing app.
///
/// ## Why there is silent audio in a controller app
///
/// iOS only shows the Now Playing card for the app that currently *owns* audio
/// output. A remote controller plays nothing locally, so
/// `MPNowPlayingInfoCenter` alone is ignored — that's the finding recorded in
/// `NOW_PLAYING_NOTES.md`, and why the Lock Screen surface there had to be a
/// Live Activity. The way around it is the one every third-party Sonos
/// controller uses: hold an active `.playback` session playing a silent loop, so
/// the system treats Clic as the playing app and renders the card, while the
/// actual audio comes out of the speakers.
///
/// Consequences, accepted deliberately:
/// - It interrupts other audio on the phone. `.mixWithOthers` would avoid that
///   but also forfeits the Now Playing claim, which is the entire feature.
/// - It needs the `audio` background mode, so the session is held only while a
///   group actually has something loaded.
///
/// ## Why this isn't driven from the view layer
///
/// The first cut hung this off a root `ViewModifier`, which was wrong: SwiftUI
/// stops evaluating bodies once the app is backgrounded, and backgrounded is
/// precisely when the Lock Screen card is the only thing on screen. Anything
/// keyed off `onChange` silently stopped updating there.
///
/// So the service owns its own observation. `activate()` arms a
/// `withObservationTracking` loop over the model state the card reflects; that
/// fires from `@Observable` regardless of whether any view is alive, and re-arms
/// after each pass. Nothing in the view tree is involved.
///
/// ## Why the WebSocket
///
/// The SOAP pulse is cancelled on background, and polling from a background
/// audio session would be the expensive way to do this. Instead the service
/// claims the `.nowPlaying` live listener: one socket, on the coordinator of the
/// group being mirrored, for `[.metadata, .playback]`. Events land in
/// `SonosService`'s handler, which writes the model and calls back through
/// `onLiveUpdate` — so the card refreshes on track and transport changes only,
/// and idles at zero cost in between. Elapsed time is *not* pushed on a timer:
/// the info center interpolates from `elapsedPlaybackTime` + `playbackRate`.
@MainActor
@Observable
final class NowPlayingSessionService {
    static let shared = NowPlayingSessionService()

    /// True while the silent session is held. `HardwareVolumeControlModifier`
    /// reads this (and re-runs, since it's observed) to stay off the audio
    /// session while this service owns it.
    private(set) var isActive = false

    @ObservationIgnored private var group: GroupRoom?
    @ObservationIgnored private var sonosService: SonosService?
    @ObservationIgnored private var silentPlayer: AVAudioPlayer?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var volumeView: MPVolumeView?
    @ObservationIgnored private var hasActivated = false
    @ObservationIgnored private var preferenceObserver: NSObjectProtocol?
    @ObservationIgnored private var lastKnownEnabled = false
    @ObservationIgnored private var observationGeneration = 0

    /// What the card is currently showing, so repeat events don't rebuild it.
    @ObservationIgnored private var published: Snapshot?
    /// The position anchor handed to the info center, and when — together they
    /// reproduce the elapsed time the system is currently interpolating.
    @ObservationIgnored private var publishedElapsed: TimeInterval = 0
    @ObservationIgnored private var publishedAt: Date = .distantPast
    /// Last `Room.playbackPosition` we saw, to tell a position the speaker just
    /// reported from one that's been frozen since the poll stopped.
    @ObservationIgnored private var lastModelElapsed: TimeInterval = -1

    /// Artwork is keyed by URL: the expensive part is decoding, and the same
    /// song can republish many times (pause, seek, volume).
    @ObservationIgnored private var publishedArtworkURL: URL?

    private struct Snapshot: Equatable {
        var title: String
        var artist: String
        var album: String
        var roomName: String
        var duration: TimeInterval
        var isPlaying: Bool
        var artworkURL: URL?
        var canSkip: Bool
        var canSkipBack: Bool
        var canSeek: Bool
    }

    private init() {}

    // MARK: - Lifecycle

    /// Call once at launch. From then on the service watches the model itself and
    /// starts, re-points, or drops the session as playback moves around — no
    /// further calls needed, including from the preference toggle (a
    /// `UserDefaults` change re-evaluates).
    func activate() {
        guard !hasActivated else { return }
        hasActivated = true

        // `didChangeNotification` fires for every `@AppStorage` write anywhere in
        // the app, so filter down to an actual change of *this* flag rather than
        // re-evaluating on unrelated preference traffic.
        lastKnownEnabled = isEnabled
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabled != self.lastKnownEnabled else { return }
                self.lastKnownEnabled = self.isEnabled
                self.evaluate()
            }
        }

        evaluate()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.lockScreenNowPlaying)
    }

    /// The group the card mirrors: the selected one, falling back to whatever is
    /// playing. The selection sticks around after the user leaves a player, so an
    /// idle selected speaker hands the card over to the music.
    ///
    /// iOS has exactly one Now Playing app and one item in it, so with several
    /// groups playing at once only one can be on the card. The fallback walks
    /// `sorted` rather than `groups`: `groups` is in Sonos topology-parse order,
    /// which is arbitrary and reshuffles when the topology refreshes — two rooms
    /// playing could hand the card back and forth on an unrelated group change.
    /// `sorted` is the same order the user sees in the speaker list (and puts
    /// playing groups first under the `.playing` sort), so the pick is stable and
    /// explicable.
    private func resolveTarget() -> GroupRoom? {
        let sonosService = SonosService.shared
        let selected = Router.main.selectedID.flatMap { id in
            sonosService.groups.first(where: { $0.coordinatorID == id })
        }
        if let selected, isMirrorable(selected) { return selected }
        return sonosService.sorted.first { $0.coordinatorRoom.isPlaying && isMirrorable($0) }
    }

    /// Makes tapping the Now Playing card land on the mirrored speaker.
    ///
    /// The card carries no tap URL — iOS just foregrounds the app, and there's no
    /// signal saying the launch came from the card — so intercepting activation
    /// would mean yanking the user to the player on *every* return to the app,
    /// including after a phone call. Instead the selection is pointed at the group
    /// while it's being mirrored, so the app is already on that speaker whenever
    /// it opens, from the card or anywhere else.
    ///
    /// Only fills a selection that isn't already showing something mirrorable:
    /// `resolveTarget` prefers the selection, so overwriting a live one would let
    /// the card drag the user off the speaker they were looking at.
    private func pointSelectionAtMirroredGroup(_ group: GroupRoom) {
        let router = Router.main
        guard router.selectedID != group.coordinatorID else { return }
        let selected = router.selectedID.flatMap { id in
            SonosService.shared.groups.first(where: { $0.coordinatorID == id })
        }
        if let selected, isMirrorable(selected) { return }
        router.selectedID = group.coordinatorID
    }

    /// TV mode has no transport to mirror and an empty track means the speaker is
    /// idle — neither is worth holding the audio session for.
    private func isMirrorable(_ group: GroupRoom) -> Bool {
        guard !group.TVMode else { return false }
        return !group.coordinatorRoom.track.isEmpty || group.coordinatorRoom.radioStation != nil
    }

    /// Everything the card reflects, read in one place so
    /// `withObservationTracking` registers exactly these and nothing more.
    /// Deliberately excludes `playbackPosition` — it ticks continuously, and the
    /// info center interpolates elapsed time on its own.
    private func trackedState() -> String {
        guard isEnabled, let group = resolveTarget() else { return "idle" }
        let room = group.coordinatorRoom
        return [
            group.coordinatorID,
            room.track.unique,
            room.track.artworkURL?.absoluteString ?? "",
            String(room.track.duration),
            String(room.isPlaying),
            room.radioStation ?? "",
            String(group.availableActions.rawValue),
        ].joined(separator: "|")
    }

    /// Re-arms after every pass: `withObservationTracking` is one-shot.
    private func evaluate() {
        defer { armObservation() }
        guard isEnabled, let group = resolveTarget() else {
            stop()
            return
        }
        run(group: group)
    }

    /// A `withObservationTracking` registration can't be cancelled, and every
    /// `evaluate()` adds one — so registrations from earlier passes stay live and
    /// all fire on the next mutation. The generation stamp retires them: only the
    /// newest one is allowed to act, and since it's the only one that re-arms,
    /// the set converges back to a single live registration.
    private func armObservation() {
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = trackedState()
        } onChange: { [weak self] in
            // onChange fires *before* the mutation lands, so read the new value
            // on the next main-actor turn.
            Task { @MainActor in
                guard let self, self.observationGeneration == generation else { return }
                self.evaluate()
            }
        }
    }

    /// Brings the session up if needed and points it at `group`. Idempotent: the
    /// steady-state path is a `publish()` that returns without touching the info
    /// center when nothing the card shows has moved.
    private func run(group: GroupRoom) {
        let sonosService = SonosService.shared

        if !isActive {
            guard activateSession() else { return }
            registerCommands()
            observeSessionEvents()
            isActive = true
            sonosService.onLiveUpdate = { [weak self] updated in
                guard let self, updated.coordinatorID == self.group?.coordinatorID else { return }
                self.publish()
            }
        }

        let isNewTarget = self.group?.coordinatorID != group.coordinatorID
        // Re-assign even for the same id: `SonosService` replaces `GroupRoom`
        // instances on topology changes, and holding the old one means writing to
        // an orphan.
        self.group = group
        self.sonosService = sonosService

        pointSelectionAtMirroredGroup(group)

        if isNewTarget {
            published = nil
            lastModelElapsed = -1
            attachVolumeBridge(group: group, sonosService: sonosService)
            Task { [weak self] in
                await sonosService.listen(to: group, as: .nowPlaying, events: [.metadata, .playback])
                self?.publish()
            }
        }

        publish()
    }

    /// Tears the session down and hands audio back to whatever was playing.
    func stop() {
        guard isActive else { return }
        isActive = false

        artworkTask?.cancel()
        artworkTask = nil
        detachVolumeBridge()
        silentPlayer?.stop()
        silentPlayer = nil
        published = nil
        lastModelElapsed = -1
        publishedArtworkURL = nil

        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        unregisterCommands()

        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()

        let sonosService = self.sonosService
        sonosService?.onLiveUpdate = nil
        self.sonosService = nil
        self.group = nil

        Task {
            await sonosService?.stopListening(as: .nowPlaying)
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Audio session

    /// `.playback` with no options: `.mixWithOthers` or `.duckOthers` would let
    /// other audio keep the Now Playing claim, which defeats the purpose.
    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Now Playing session failed to activate: \(error.localizedDescription)")
            return false
        }
        return startSilentLoop()
    }

    private func startSilentLoop() -> Bool {
        do {
            let player = try AVAudioPlayer(
                data: Self.silentPCMWAV(seconds: 1),
                fileTypeHint: AVFileType.wav.rawValue
            )
            player.numberOfLoops = -1
            player.volume = 0
            guard player.play() else { return false }
            silentPlayer = player
            return true
        } catch {
            print("Now Playing silent loop failed: \(error.localizedDescription)")
            return false
        }
    }

    /// One second of 44.1 kHz mono PCM silence with a WAV header, built in
    /// memory — no bundled asset to keep in sync across targets.
    private static func silentPCMWAV(seconds: Double) -> Data {
        let sampleRate = 44_100
        let channels = 1
        let bitsPerSample = 16
        let bytesPerFrame = channels * bitsPerSample / 8
        let audioBytes = Int(Double(sampleRate) * seconds) * bytesPerFrame

        var data = Data(capacity: 44 + audioBytes)
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + audioBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)                                     // PCM header length
        append16(1)                                      // PCM, uncompressed
        append16(UInt16(channels))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * bytesPerFrame))     // byte rate
        append16(UInt16(bytesPerFrame))                  // block align
        append16(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(audioBytes))
        data.append(Data(count: audioBytes))
        return data
    }

    /// A phone call (or Siri, or another app grabbing output) suspends the
    /// silent loop; without resuming it the card silently disappears. Media
    /// services resetting invalidates the player entirely.
    private func observeSessionEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in self?.resumeSilentLoop() }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.silentPlayer = nil
                _ = self.activateSession()
                self.published = nil
                self.publish()
            }
        })
    }

    /// Re-takes the audio session after another part of the app borrowed it (a
    /// 30-second song preview ducks and then deactivates on teardown, which
    /// would otherwise drop the Now Playing claim with it).
    func reclaimSession() {
        guard isActive else { return }
        resumeSilentLoop()
    }

    private func resumeSilentLoop() {
        guard isActive else { return }
        let session = AVAudioSession.sharedInstance()
        // The borrower may have left a different category behind (`.duckOthers`
        // in the preview's case), which forfeits the Now Playing claim.
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        if silentPlayer?.play() != true {
            silentPlayer = nil
            _ = activateSession()
        }
        published = nil
        publish()
    }

    // MARK: - Volume

    /// While the session is held, the phone's own volume is inaudible — nothing
    /// plays but silence — so the hardware buttons and the Lock Screen slider
    /// are re-pointed at the group's volume. This is the same
    /// `HardwareVolumeService` the player screen uses, run in its
    /// session-borrowing mode; the `MPVolumeView` has to live in a window for
    /// its slider to exist, so it's parked in the key window rather than
    /// plumbed through SwiftUI.
    private func attachVolumeBridge(group: GroupRoom, sonosService: SonosService) {
        // Backgrounded, no window is key any more — any window in the scene will
        // do, it only has to host the slider.
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }

        if volumeView?.window == nil {
            volumeView?.removeFromSuperview()
            let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
            view.alpha = 0.0001
            view.isUserInteractionEnabled = false
            window.addSubview(view)
            volumeView = view
        }

        guard let volumeView else { return }
        HardwareVolumeService.shared.start(
            group: group,
            sonosService: sonosService,
            volumeView: volumeView,
            ownsAudioSession: false
        )
    }

    private func detachVolumeBridge() {
        guard volumeView != nil else { return }
        HardwareVolumeService.shared.stop()
        volumeView?.removeFromSuperview()
        volumeView = nil
    }

    // MARK: - Now Playing info

    /// Rebuilds the card, skipping the write when nothing the card shows has
    /// changed. Position is refreshed on every accepted publish — cheap, and it
    /// re-anchors the system's interpolation after a seek or a skip.
    private func publish() {
        guard isActive, let group else { return }
        let room = group.coordinatorRoom
        let track = room.track

        // An idle radio player reports an empty track between songs; the station
        // name is what the rest of the app shows there, so match it.
        let title = !track.song.isEmpty ? track.song : (room.radioStation ?? group.nameWithCount)
        let snapshot = Snapshot(
            title: title,
            artist: track.artist,
            // The album line is the only spare row on the card — when the track
            // has no album (radio, TV, line-in) it's more useful as the speaker.
            album: track.album.isEmpty ? group.nameWithCount : track.album,
            roomName: group.nameWithCount,
            duration: track.duration,
            isPlaying: room.isPlaying,
            artworkURL: track.artworkURL,
            // An empty action set means "not fetched yet", not "nothing is
            // allowed" — `getCurrentTransportActions` only lands on the first
            // `updateGroups` pass. Treating unknown as unavailable stripped the
            // skip buttons off the card on launch and never put them back.
            canSkip: allows(.next, in: group),
            canSkipBack: allows(.previous, in: group),
            canSeek: allows(.scrubbable, in: group)
        )

        // The info center interpolates elapsed time from the last anchor and the
        // playback rate, so a republish is only needed when the card's content
        // changed or when the *speaker* reported a position that disagrees with
        // what the system is already showing (a seek, or a skip we didn't
        // initiate).
        //
        // `modelMoved` is what makes that safe. `Room.playbackPosition` only
        // advances when something writes it — the socket, or the SOAP poll, which
        // is cancelled while backgrounded. So in the background the model sits
        // frozen at the last reported position while the system's interpolation
        // correctly moves on. Re-anchoring on that difference would drag the
        // scrubber back to the frozen value every time, which reads as playback
        // having stopped. Only a position the speaker has actually updated is
        // worth re-anchoring to.
        let elapsed = room.playbackPosition
        let modelMoved = elapsed != lastModelElapsed
        lastModelElapsed = elapsed
        let interpolated = published?.isPlaying == true
            ? publishedElapsed + Date.now.timeIntervalSince(publishedAt) * 1000
            : publishedElapsed
        let drifted = modelMoved && abs(elapsed - interpolated) > 2000
        guard snapshot != published || drifted else { return }

        if snapshot != published {
            updateCommandAvailability(snapshot)
        }
        published = snapshot
        publishedElapsed = elapsed
        publishedAt = .now

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.artist,
            MPMediaItemPropertyAlbumTitle: snapshot.album,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]

        // Sonos reports positions and durations in milliseconds.
        if snapshot.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration / 1000
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = room.playbackPosition / 1000
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
        } else {
            // Radio and line-in have no timeline — a duration of 0 would render
            // as a scrubber pinned at the start.
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }

        // Keep the existing artwork attached across republishes; loadArtwork
        // replaces it once a new URL resolves.
        if let artwork = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork],
           publishedArtworkURL == snapshot.artworkURL {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = snapshot.isPlaying ? .playing : .paused
        #if DEBUG
        logDiagnostics("published \(snapshot.title)")
        #endif

        if publishedArtworkURL != snapshot.artworkURL {
            loadArtwork(from: snapshot.artworkURL)
        }
    }

    /// Loads through the shared Nuke pipeline, so the image is usually already
    /// in memory from the player screen.
    private func loadArtwork(from url: URL?) {
        artworkTask?.cancel()
        publishedArtworkURL = url

        guard let url else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = nil
            return
        }

        let request = ImageRequest(url: url, processors: [.resize(width: 600)], priority: .high)
        if let cached = ImagePipeline.shared.cache.cachedImage(for: request)?.image {
            attach(artwork: cached, for: url)
            return
        }

        artworkTask = Task { [weak self] in
            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            guard !Task.isCancelled else { return }
            self?.attach(artwork: image, for: url)
        }
    }

    private func attach(artwork image: UIImage, for url: URL) {
        // A slower load for the previous song must not overwrite the current one.
        guard publishedArtworkURL == url else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
    }

    #if DEBUG
    /// The card's contents and its control row come from two different places —
    /// `nowPlayingInfo` and the command centre — and a missing button looks
    /// identical to a missing session. This prints both so they can be told
    /// apart from the console.
    private func logDiagnostics(_ context: String) {
        let session = AVAudioSession.sharedInstance()
        let center = MPRemoteCommandCenter.shared()
        let info = MPNowPlayingInfoCenter.default()
        print("""
        🎛 NowPlaying — \(context)
           session: category=\(session.category.rawValue) active=\(silentPlayer?.isPlaying == true) \
        otherAudio=\(session.isOtherAudioPlaying)
           commands: play=\(center.playCommand.isEnabled) pause=\(center.pauseCommand.isEnabled) \
        toggle=\(center.togglePlayPauseCommand.isEnabled) next=\(center.nextTrackCommand.isEnabled) \
        prev=\(center.previousTrackCommand.isEnabled) scrub=\(center.changePlaybackPositionCommand.isEnabled)
           info: rate=\(info.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] ?? "nil") \
        duration=\(info.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] ?? "nil") \
        state=\(info.playbackState.rawValue)
        """)
    }
    #endif

    // MARK: - Remote commands

    /// Handlers are delivered on the main thread, hence `assumeIsolated` rather
    /// than hopping — a hop would return `.success` before we know the group is
    /// even there, and the system uses the status to decide whether to flash the
    /// control.
    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()

        // Enabled up front, not left to the first `publish()`. iOS reads the
        // command set when it builds the card, which can happen before any
        // playback state has been resolved — a command that isn't enabled by
        // then simply has no button, and enabling it later doesn't always bring
        // the row back.
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.perform("play") { service, group in await service.play(ip: group.ip) } ?? .commandFailed
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.perform("pause") { service, group in await service.pause(ip: group.ip) } ?? .commandFailed
            }
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.perform("toggle") { service, group in await service.togglePlayPause(for: group) } ?? .commandFailed
            }
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.perform("next") { service, group in
                    group.coordinatorRoom.playbackPosition = 0
                    await service.next(ip: group.ip)
                } ?? .commandFailed
            }
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.perform("previous") { service, group in
                    group.coordinatorRoom.playbackPosition = 0
                    await service.previous(ip: group.ip)
                } ?? .commandFailed
            }
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let milliseconds = event.positionTime * 1000
            return MainActor.assumeIsolated {
                self?.perform("scrub") { service, group in
                    group.coordinatorRoom.updatePlaybackPosition(milliseconds)
                    await service.seek(to: milliseconds, on: group)
                } ?? .commandFailed
            }
        }

        // Nothing here maps onto a Sonos transport — leaving them enabled makes
        // the card offer controls that silently do nothing.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.changeRepeatModeCommand.isEnabled = false
        center.changeShuffleModeCommand.isEnabled = false
    }

    private func allows(_ action: AvailableActions, in group: GroupRoom) -> Bool {
        group.availableActions.isEmpty || group.availableActions.contains(action)
    }

    private func updateCommandAvailability(_ snapshot: Snapshot) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = snapshot.canSkip
        center.previousTrackCommand.isEnabled = snapshot.canSkipBack
        center.changePlaybackPositionCommand.isEnabled = snapshot.canSeek && snapshot.duration > 0
    }

    private func unregisterCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
    }

    /// Runs a transport command against the mirrored group and repaints the card
    /// immediately, so the Lock Screen doesn't sit on the old state waiting for
    /// the speaker to echo back.
    private func perform(
        _ name: String,
        _ action: @escaping (SonosService, GroupRoom) async -> Void
    ) -> MPRemoteCommandHandlerStatus {
        #if DEBUG
        // Proves the command centre is actually reaching us. A card that draws no
        // buttons and a command centre that isn't wired look the same from the
        // outside — but AirPods, a headset button, CarPlay, or the Control Centre
        // module will all land here even when the Lock Screen draws nothing.
        print("🎛 NowPlaying — command \(name) received")
        #endif
        guard let sonosService, let group else { return .noSuchContent }
        Task { @MainActor in
            await action(sonosService, group)
            publish()
        }
        return .success
    }
}
#endif
