#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import Defaults
import MediaPlayer
import Nuke
import Observation
import os
import SonosKit
import SubscriptionKit
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
/// `SonosService`'s handler, which writes the model and calls back through the
/// `.nowPlaying` live-update observer — so the card refreshes on track and
/// transport changes only, and idles at zero cost in between.
///
/// ## What lives elsewhere
///
/// - `SilentAudioSession` — the audio claim itself, its recovery from
///   interruptions, and the silence it plays.
/// - `PlaybackPositionAnchor` — when to re-state elapsed time, and what to
///   state. Subtler than it looks; read its notes before touching it.
/// - `AudioSessionArbiter` — how a song preview hands the session back without
///   knowing this type exists.
/// File scope so nothing here has to reason about actor isolation to log, and
/// so the formatting cost is only paid when the log is actually collected —
/// unlike `print`, which builds its string every time.
private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.nick.Clic",
    category: "NowPlaying"
)

@MainActor
@Observable
final class NowPlayingSessionService {
    static let shared = NowPlayingSessionService()

    /// True while the silent session is held.
    private(set) var isActive = false

    @ObservationIgnored private var group: GroupRoom?
    @ObservationIgnored private let audioSession = SilentAudioSession()
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var volumeView: MPVolumeView?
    @ObservationIgnored private var hasActivated = false
    @ObservationIgnored private var isStartingSession = false
    /// Retires an in-flight session bring-up when `stop()` beats it.
    @ObservationIgnored private var sessionGeneration = 0
    @ObservationIgnored private var lastKnownPreference = false
    @ObservationIgnored private var observationGeneration = 0
    /// Preference and app-state notification loops, for the life of the process.
    @ObservationIgnored private var observerTasks: [Task<Void, Never>] = []
    /// Drives the target pick — the selection wins on screen, the music wins on
    /// the Lock Screen. See `resolveTarget`.
    @ObservationIgnored private var isForeground = true

    /// What the card is currently showing, so repeat events don't rebuild it.
    @ObservationIgnored private var published: Snapshot?
    /// Owns the elapsed-time maths — see `PlaybackPositionAnchor` for why it
    /// isn't as simple as publishing the speaker's number.
    @ObservationIgnored private var positionAnchor = PlaybackPositionAnchor()

    /// Favorite state behind `likeCommand`, and the track it belongs to.
    @ObservationIgnored private var isFavorite = false
    @ObservationIgnored private var favoriteTrackID: String?
    @ObservationIgnored private var favoriteTask: Task<Void, Never>?
    /// Addressing of the declared subscription, to skip re-declaring it on
    /// every observation pass. Correctness lives in the registry, not here.
    @ObservationIgnored private var subscribedKey: String?

    /// Artwork is keyed by URL: the expensive part is decoding, and the same
    /// song can republish many times (pause, seek, volume).
    @ObservationIgnored private var publishedArtworkURL: URL?
    @ObservationIgnored private var publishedArtwork: MPMediaItemArtwork?

    private struct Snapshot: Equatable {
        var title: String
        var artist: String
        var album: String
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

        lastKnownPreference = isPreferenceOn
        isForeground = UIApplication.shared.applicationState != .background

        let center = NotificationCenter.default
        // Async sequences rather than block observers: the loop bodies inherit
        // this actor, so there are no tokens to retain and no `assumeIsolated`
        // to be wrong about. These live for the process — the audio-session
        // observers, which do get torn down, belong to `SilentAudioSession`.
        observerTasks = [
            // `didChangeNotification` fires for every `@AppStorage` write
            // anywhere in the app, so filter to an actual change of *this* flag.
            // Only the preference is compared — the subscription half of
            // `isEnabled` is observed, and arrives through `trackCardState`.
            Task { [weak self] in
                for await _ in center.notifications(
                    named: UserDefaults.didChangeNotification,
                    object: UserDefaults.standard
                ) {
                    guard let self, self.isPreferenceOn != self.lastKnownPreference else { continue }
                    self.lastKnownPreference = self.isPreferenceOn
                    self.evaluate()
                }
            },
            // Which group the card mirrors depends on foreground vs background
            // (see `resolveTarget`), so both transitions re-pick.
            Task { [weak self] in
                for await _ in center.notifications(named: UIApplication.didEnterBackgroundNotification) {
                    self?.isForeground = false
                    self?.evaluate()
                }
            },
            Task { [weak self] in
                for await _ in center.notifications(named: UIApplication.willEnterForegroundNotification) {
                    self?.isForeground = true
                    self?.evaluate()
                }
            },
        ]

        evaluate()
    }

    private var isPreferenceOn: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.lockScreenNowPlaying)
    }

    /// Clic Super, and the preference. Gated here rather than only at the toggle
    /// so a subscription that lapses while the preference is still on tears the
    /// session down — the toggle can't be the source of truth for something that
    /// keeps running with the app closed.
    ///
    /// `trackCardState` reads this, so the `@Observable` subscription write on
    /// purchase or expiry re-evaluates on its own.
    private var isEnabled: Bool {
        isPreferenceOn && SubscriptionService.shared.subscription.isActive
    }

    /// The group the card mirrors. iOS has exactly one Now Playing app and one
    /// item in it, so with several groups playing only one of them can be on the
    /// card — this is the pick, and it depends on where the user is:
    ///
    /// - **Foreground:** the selected group wins, even paused. The user is
    ///   looking at a speaker, and the hardware volume bridge follows the card,
    ///   so the buttons have to control the speaker on screen.
    /// - **Background:** the playing group wins. The card is all the user can
    ///   see, so it should follow the music; a paused selection is only the
    ///   fallback for when nothing is playing at all.
    ///
    /// The playing scan walks `sorted`, not `groups`: `groups` is in Sonos
    /// topology-parse order, which is arbitrary and reshuffles when the topology
    /// refreshes — two rooms playing could hand the card back and forth on an
    /// unrelated group change. `sorted` is the order the user sees in the speaker
    /// list, so the pick is stable and explicable.
    private func resolveTarget() -> GroupRoom? {
        let sonosService = SonosService.shared
        let selected = Router.main.selectedID.flatMap { id in
            sonosService.groups.first(where: { $0.coordinatorID == id })
        }
        if isForeground, let selected, isMirrorable(selected) { return selected }
        if let playing = sonosService.sorted.first(where: { $0.coordinatorRoom.isPlaying && isMirrorable($0) }) {
            return playing
        }
        // Nothing playing anywhere — keep the selection up rather than dropping
        // the card, so its transport can start it again.
        if let selected, isMirrorable(selected) { return selected }
        return nil
    }

    /// TV mode has no transport to mirror and an empty track means the speaker is
    /// idle — neither is worth holding the audio session for.
    private func isMirrorable(_ group: GroupRoom) -> Bool {
        guard !group.TVMode else { return false }
        return !group.coordinatorRoom.track.isEmpty || group.coordinatorRoom.radioStation != nil
    }

    /// Touches everything the card reflects that `resolveTarget()` didn't
    /// already read, so `withObservationTracking` registers on all of it.
    ///
    /// The reads are the point — nothing is returned, because building a value
    /// out of them would allocate on every model change for something no one
    /// looks at. `playbackPosition` is deliberately absent: it ticks, and the
    /// info center interpolates elapsed time on its own.
    private func trackCardState(of group: GroupRoom) {
        let room = group.coordinatorRoom
        // The socket is addressed by group id and ip, both of which move without
        // the coordinator changing (grouping, DHCP) — see `run`.
        _ = group.id
        _ = group.ip
        _ = room.track.unique
        _ = room.track.artworkURL
        _ = room.track.duration
        _ = room.radioStation
        _ = group.availableActions
        // Not shown on the card, but the volume bridge mirrors it onto the
        // phone's slider — so a change made on the speaker, in the Sonos app, or
        // anywhere else in Clic has to reach `syncSystemVolume`.
        _ = group.groupVolume
        // Every favorite path writes this store, so reading it is what makes a
        // like made on the player screen reach `likeCommand`, and vice versa.
        _ = LiveActivityFavoriteStore.shared.get(room.track.trackID)
    }

    /// One pass: resolve the target, register observation on exactly the reads
    /// that produced it, then act.
    ///
    /// Resolving *inside* the tracking closure is what keeps this to a single
    /// pass — `resolveTarget()` scans (and sorts) the groups, so doing it once
    /// for the decision and again to register the reads doubled that work on
    /// every model change.
    ///
    /// A `withObservationTracking` registration can't be cancelled and each pass
    /// adds one, so registrations from earlier passes stay live and all fire on
    /// the next mutation. The generation stamp retires them: only the newest is
    /// allowed to act, and since it's the only one that re-arms, the set
    /// converges back to a single live registration.
    private func evaluate() {
        observationGeneration += 1
        let generation = observationGeneration

        var target: GroupRoom?
        withObservationTracking {
            target = isEnabled ? resolveTarget() : nil
            if let target { trackCardState(of: target) }
        } onChange: { [weak self] in
            // onChange fires *before* the mutation lands, so read the new value
            // on the next main-actor turn.
            Task { @MainActor in
                guard let self, self.observationGeneration == generation else { return }
                self.evaluate()
            }
        }

        guard let target else {
            stop()
            return
        }
        run(group: target)
    }

    /// Brings the session up if needed and points it at `group`. Idempotent: the
    /// steady-state path is a `publish()` that returns without touching the info
    /// center when nothing the card shows has moved.
    private func run(group: GroupRoom) {
        let sonosService = SonosService.shared

        beginSessionIfNeeded()

        let isNewTarget = self.group?.coordinatorID != group.coordinatorID
        // Re-assign even for the same id: `SonosService` replaces `GroupRoom`
        // instances on topology changes, and holding the old one means writing to
        // an orphan.
        self.group = group

        // Nothing here writes `Router.main.selectedID`. It used to, so that a tap
        // on the card landed on the mirrored speaker — but the selection is also
        // how the speaker list drives navigation, and popping back to the list
        // sets it to nil. That fired this observation, which wrote the id
        // straight back and pushed the player again, so there was no way out of
        // the player. The card is a mirror; it only reads.

        if isNewTarget {
            published = nil
            positionAnchor.reset()
            attachVolumeBridge(group: group)
        }

        // Re-declared on any change to the socket's addressing, not just a
        // change of coordinator: Sonos subscribes playback and metadata *per
        // group id*, and that id changes when speakers are grouped or ungrouped
        // even though the coordinator stays put. The registry is what enforces
        // this — it compares the whole subscription — so this key is only here to
        // avoid spawning a Task per observation pass to tell it nothing changed.
        let subscriptionKey = "\(group.coordinatorID)|\(group.id)|\(group.ip)"
        if subscribedKey != subscriptionKey {
            subscribedKey = subscriptionKey
            Task { [weak self] in
                await sonosService.listen(to: group, as: .nowPlaying, events: [.metadata, .playback])
                self?.publish()
            }
        }

        // Group volume is tracked, so this runs whenever it moves.
        HardwareVolumeService.shared.syncSystemVolume()
        publish()
    }

    /// Takes the audio session, then wires everything that depends on holding
    /// it. Asynchronous because activation is a synchronous XPC round trip to
    /// mediaserverd that would otherwise land on the main actor during launch;
    /// the rest of `run` doesn't depend on it, and `publish()` no-ops until
    /// `isActive`.
    private func beginSessionIfNeeded() {
        guard !isActive, !isStartingSession else { return }
        isStartingSession = true
        sessionGeneration += 1
        let generation = sessionGeneration

        Task { [weak self] in
            guard let self else { return }
            let started = await self.audioSession.start()
            self.isStartingSession = false

            // `stop()` may have run while the session was coming up.
            guard self.sessionGeneration == generation else {
                if started { self.audioSession.stop() }
                return
            }
            guard started else { return }

            self.audioSession.onRestored = { [weak self] in
                // Whatever interrupted us may have invalidated the card.
                self?.published = nil
                self?.publish()
            }
            self.registerCommands()
            // Anything that borrows the session (a song preview) hands it back
            // here instead of deactivating it, without naming this type.
            AudioSessionArbiter.shared.claim { [weak self] in
                Task { await self?.audioSession.reclaim() }
            }
            SonosService.shared.observeLiveUpdates(as: .nowPlaying) { [weak self] _ in
                self?.publish()
            }

            self.isActive = true
            self.published = nil
            self.publish()
        }
    }

    /// Tears the session down and hands audio back to whatever was playing.
    func stop() {
        // Bumped unconditionally: a bring-up may still be in flight, and it
        // checks this before claiming anything.
        sessionGeneration += 1
        // `isActive` alone isn't the test. `run()` subscribes the socket and
        // takes the volume bridge before the session finishes coming up, so
        // stopping in that window has real cleanup to do even though the session
        // was never held. `group` is set on the same path, so it's the honest
        // "is there anything here" check — and it keeps the idle case, where
        // this is called on every pass, free.
        guard isActive || group != nil else { return }
        isActive = false

        artworkTask?.cancel()
        artworkTask = nil
        favoriteTask?.cancel()
        favoriteTask = nil
        favoriteTrackID = nil
        isFavorite = false
        subscribedKey = nil
        detachVolumeBridge()
        audioSession.onRestored = nil
        audioSession.stop()
        published = nil
        positionAnchor.reset()
        publishedArtworkURL = nil
        publishedArtwork = nil

        AudioSessionArbiter.shared.resign()
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        unregisterCommands()

        let sonosService = SonosService.shared
        sonosService.removeLiveUpdateObserver(.nowPlaying)
        self.group = nil

        Task {
            await sonosService.stopListening(as: .nowPlaying)
        }
    }

    // MARK: - Volume

    /// While the session is held, the phone's own volume is inaudible — nothing
    /// plays but silence — so the hardware buttons and the Lock Screen slider
    /// are re-pointed at the group's volume. This is the same
    /// `HardwareVolumeService` the player screen uses, run in its
    /// session-borrowing mode; the `MPVolumeView` has to live in a window for
    /// its slider to exist, so it's parked in the key window rather than
    /// plumbed through SwiftUI.
    private func attachVolumeBridge(group: GroupRoom) {
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
            sonosService: SonosService.shared,
            volumeView: volumeView,
            as: .session,
            mode: .absoluteMirror,
            configuresAudioSession: false
        )
    }

    private func detachVolumeBridge() {
        guard volumeView != nil else { return }
        HardwareVolumeService.shared.stop(as: .session)
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

        // Ahead of the dedupe guard below: a no-op unless the song changed, and
        // it has to run even on publishes the card itself skips.
        refreshFavorite(for: track)

        // An idle radio player reports an empty track between songs; the station
        // name is what the rest of the app shows there, so match it.
        let title = !track.song.isEmpty ? track.song : (room.radioStation ?? group.nameWithCount)
        // The room goes on the artist line because that's the only subtitle the
        // Lock Screen card actually renders — it shows title and artist and stops
        // there. The album line still carries the real album for the surfaces
        // that do show it (Control Centre, CarPlay), so nothing is lost by
        // borrowing this one.
        let artistLine = [track.artist, group.nameWithCount]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        let snapshot = Snapshot(
            title: title,
            artist: artistLine,
            album: track.album,
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

        // Elapsed time is not pushed on a timer — the info center interpolates
        // from the anchor and the rate — so a republish is only needed when the
        // card's content changed, or when the speaker reported a position far
        // enough from what the system already shows to be worth correcting.
        let position = positionAnchor.resolve(
            modelElapsed: room.playbackPosition,
            duration: snapshot.duration
        )
        guard snapshot != published || position.drifted else { return }

        if snapshot != published {
            updateCommandAvailability(snapshot)
        }
        published = snapshot
        positionAnchor.commit(elapsed: position.elapsed, isPlaying: snapshot.isPlaying)

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
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.elapsed / 1000
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
        } else {
            // Radio and line-in have no timeline — a duration of 0 would render
            // as a scrubber pinned at the start.
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }

        // Carry the artwork across republishes. Held locally rather than read
        // back out of `nowPlayingInfo`, whose getter copies the whole dictionary
        // across to MediaRemote.
        if let publishedArtwork, publishedArtworkURL == snapshot.artworkURL {
            info[MPMediaItemPropertyArtwork] = publishedArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = snapshot.isPlaying ? .playing : .paused
        logDiagnostics("published")

        if publishedArtworkURL != snapshot.artworkURL {
            loadArtwork(from: snapshot.artworkURL, track: track)
        }
    }

    /// Loads through the shared Nuke pipeline, so the image is usually already
    /// in memory from the player screen.
    /// Mirrors `ArtworkView.imageIDKey` — album, else track name, else id, else
    /// the URL — so both surfaces name the same cache entry.
    private func artworkCacheKey(for track: Track) -> String {
        let service = String(describing: track.musicService)
        if !track.album.isEmpty { return "\(track.album).\(service).player" }
        if !track.name.isEmpty { return "\(track.name).\(service).player" }
        if !track.trackID.isEmpty { return track.trackID + ".player" }
        return (track.artworkURL?.absoluteString ?? "") + ".player"
    }

    private func loadArtwork(from url: URL?, track: Track) {
        artworkTask?.cancel()
        publishedArtworkURL = url

        guard let url else {
            publishedArtwork = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = nil
            return
        }

        // Same key and processor as `ArtworkView`, so this hits the entry the
        // player screen populated rather than downloading and decoding a second
        // copy of the same image on every track change.
        let request = ImageRequest(
            url: url,
            processors: [.resize(width: 500)],
            priority: .high,
            userInfo: [.imageIdKey: artworkCacheKey(for: track)]
        )
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
        publishedArtwork = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
    }

    /// The card's contents and its control row come from two different places —
    /// `nowPlayingInfo` and the command centre — and a missing button looks
    /// identical to a missing session. This records both so they can be told
    /// apart.
    ///
    /// `Logger` rather than `print`: the interpolations aren't evaluated unless
    /// something is collecting, so this costs nothing in a release build and
    /// doesn't need a `#if DEBUG` fence around every call site.
    private func logDiagnostics(_ context: String) {
        let center = MPRemoteCommandCenter.shared()
        let info = MPNowPlayingInfoCenter.default()
        // One line rather than a multi-line literal: `OSLogMessage` needs a
        // static format string, and folded literals are a known source of
        // trouble there.
        log.debug("\(context, privacy: .public) — held=\(self.audioSession.isHeld), play=\(center.playCommand.isEnabled), pause=\(center.pauseCommand.isEnabled), toggle=\(center.togglePlayPauseCommand.isEnabled), next=\(center.nextTrackCommand.isEnabled), prev=\(center.previousTrackCommand.isEnabled), scrub=\(center.changePlaybackPositionCommand.isEnabled), state=\(info.playbackState.rawValue)")
    }

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

        // Favorites the playing song on whichever service it came from, the same
        // as the player's heart/star. `isActive` carries the current state and
        // each invocation toggles it. Surfaces that render feedback commands
        // (CarPlay, some head units and accessories) get it; the iOS Lock Screen
        // card has no slot for an app button, so it doesn't appear there.
        center.likeCommand.localizedTitle = "Favorite"
        center.likeCommand.localizedShortTitle = "Favorite"
        center.likeCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.toggleFavorite() ?? .commandFailed
            }
        }

        // Nothing here maps onto a Sonos transport — leaving them enabled makes
        // the card offer controls that silently do nothing. `dislike` included:
        // no service Clic talks to takes a negative signal.
        center.dislikeCommand.isEnabled = false
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

    /// Points `likeCommand` at `track`, once per song.
    ///
    /// Goes through `MusicSearchService.isFavorite`/`setFavorite` — the same
    /// per-service dispatch (Apple / Spotify / SoundCloud / Deezer /
    /// Plex-by-rating) the player's heart uses — so a favorite made here and one
    /// made in the app can't diverge. `LiveActivityFavoriteStore` seeds the state
    /// instantly; without it the control would read "not favorited" for as long
    /// as the service lookup takes.
    private func refreshFavorite(for track: Track) {
        let command = MPRemoteCommandCenter.shared().likeCommand

        guard canFavorite(track) else {
            favoriteTask?.cancel()
            favoriteTask = nil
            favoriteTrackID = nil
            isFavorite = false
            command.isEnabled = false
            command.isActive = false
            return
        }

        command.isEnabled = true
        let stored = LiveActivityFavoriteStore.shared.get(track.trackID)

        // Same song: follow the store. It's written by every favorite path —
        // the player's heart, the context menus, this command — so this is how a
        // like made on the player screen reaches the card without either side
        // knowing about the other. The observation pass reads the store too, so the
        // write wakes the observation that lands here.
        guard favoriteTrackID != track.trackID else {
            if let stored, stored != isFavorite {
                isFavorite = stored
                command.isActive = stored
            }
            return
        }

        favoriteTrackID = track.trackID
        isFavorite = stored ?? false
        command.isActive = isFavorite

        favoriteTask?.cancel()
        favoriteTask = Task { [weak self] in
            let favorite = await MusicSearchService.shared.isFavorite(
                trackID: track.trackID,
                service: track.musicService
            )
            guard !Task.isCancelled, let self, self.favoriteTrackID == track.trackID else { return }
            self.isFavorite = favorite
            MPRemoteCommandCenter.shared().likeCommand.isActive = favorite
        }
    }

    private func canFavorite(_ track: Track) -> Bool {
        track.musicService.supportsFavoriteTrack && !track.trackID.isEmpty
    }

    private func toggleFavorite() -> MPRemoteCommandHandlerStatus {
        guard let track = group?.coordinatorRoom.track, canFavorite(track) else { return .noSuchContent }

        log.debug("command favorite received")

        // Optimistic, like every other favorite surface: the write is
        // fire-and-forget from the user's point of view.
        let favorite = !isFavorite
        isFavorite = favorite
        MPRemoteCommandCenter.shared().likeCommand.isActive = favorite
        Task {
            await MusicSearchService.shared.setFavorite(
                favorite,
                trackID: track.trackID,
                service: track.musicService
            )
        }
        return .success
    }

    /// Only the commands whose availability actually varies — play/pause/toggle
    /// are enabled once in `registerCommands` and never conditional.
    private func updateCommandAvailability(_ snapshot: Snapshot) {
        let center = MPRemoteCommandCenter.shared()
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
        center.likeCommand.removeTarget(nil)
        center.likeCommand.isEnabled = false
        center.likeCommand.isActive = false
    }

    /// Runs a transport command against the mirrored group and repaints the card
    /// immediately, so the Lock Screen doesn't sit on the old state waiting for
    /// the speaker to echo back.
    private func perform(
        _ name: String,
        _ action: @escaping (SonosService, GroupRoom) async -> Void
    ) -> MPRemoteCommandHandlerStatus {
        // Proves the command centre is actually reaching us. A card that draws no
        // buttons and a command centre that isn't wired look the same from the
        // outside — but AirPods, a headset button, CarPlay, or the Control Centre
        // module all land here even when the Lock Screen draws nothing.
        log.debug("command \(name, privacy: .public) received")
        guard let group else { return .noSuchContent }
        Task { @MainActor in
            await action(SonosService.shared, group)
            publish()
        }
        return .success
    }
}
#endif
