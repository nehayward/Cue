#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import Foundation
import OSLog

/// Only failures are logged. Taking the session is the whole feature, so a
/// refusal is worth a breadcrumb; everything else is silent.
private let logger = Logger(subsystem: "com.cue", category: "NowPlaying")

/// Holds an active `.playback` audio session playing silence, so iOS treats this
/// app as the one producing audio.
///
/// That claim is the only way a controller app appears on the system Now Playing
/// card: iOS renders it for whichever app owns audio output, and an app that
/// plays nothing owns nothing, no matter what it writes to
/// `MPNowPlayingInfoCenter`. The audio itself is inaudible and irrelevant — it
/// exists to be the claim.
///
/// Split out of `NowPlayingSessionService` because none of this knows anything
/// about Sonos, Now Playing, or SwiftUI: it's an audio-session lifecycle and a
/// WAV encoder, and it's testable and replaceable on its own terms.
///
/// The on-device player uses one too, mixed with others, for Apple Music in a
/// car (`CarAudioClaim`).
@MainActor
final class SilentAudioSession {
    /// The category options the session is taken with. None for the Sonos
    /// mirror, which needs the Now Playing claim (see `configureSession`);
    /// `.mixWithOthers` for `CarAudioClaim`, which must never interrupt the
    /// music it plays beside.
    private let options: AVAudioSession.CategoryOptions

    init(options: AVAudioSession.CategoryOptions = []) {
        self.options = options
    }

    /// Called after the session has been re-established following something that
    /// interrupted it. The owner uses it to republish whatever state the
    /// interruption may have invalidated.
    var onRestored: (() -> Void)?

    private var player: AVAudioPlayer?
    /// The rate `player`'s buffer was built at, so `reclaim()` can tell a route
    /// that changed the hardware rate from one that didn't. See `startLoop`.
    private var playerSampleRate: Int?
    /// One task per notification stream; cancelling them is the teardown, so
    /// there are no observer tokens to keep straight.
    private var interruptionTasks: [Task<Void, Never>] = []

    private(set) var isHeld = false
    /// What the loop is *supposed* to be doing. Kept separately from
    /// `player.isPlaying` because a reclaim rebuilds the player and has to put it
    /// back into the state the remote transport is in, not into playing.
    private(set) var isPlaying = false

    // MARK: - Lifecycle

    /// Takes the session. Returns false if the system refused it, in which case
    /// nothing is held and the caller should not proceed.
    ///
    /// Async because `setActive` is a synchronous XPC round trip to
    /// mediaserverd — routinely 100 ms, longer when it has to interrupt other
    /// audio — and this runs during launch. Only the session call goes off the
    /// main actor; the player is built here, where it's a cheap in-memory init.
    @discardableResult
    func start() async -> Bool {
        guard !isHeld else { return true }
        guard await Self.configureSession(options: options), startLoop() else { return false }
        observeInterruptions()
        isHeld = true
        // Starts playing on purpose: the card is only created once audio has
        // actually begun. The owner's first `publish()` pauses the loop
        // immediately if the speaker is paused.
        isPlaying = true
        return true
    }

    /// Mirrors the remote transport onto the silent loop.
    ///
    /// This is not cosmetic, and it is not about the sound — there isn't any.
    /// iOS decides what the Now Playing card renders from the *audio session*,
    /// not from `MPNowPlayingInfoCenter` alone: an app whose session is actively
    /// rendering audio is playing, whatever it writes to `playbackState`. So a
    /// loop that never pauses pins the card to "playing" and silently discards
    /// every `rate = 0` we publish. Pausing the loop is what makes a pause
    /// visible.
    ///
    /// The session itself stays active. That's the distinction between this and
    /// `stop()`: a paused player with a live session is exactly the state a
    /// music app sits in when the user pauses it, and the card stays ours.
    /// Deactivating would hand it away.
    func setPlaying(_ playing: Bool) {
        guard isHeld, isPlaying != playing else { return }
        isPlaying = playing
        if playing {
            // A reclaim can leave no player behind; rebuild rather than no-op,
            // or the card would go stale from here on.
            if player?.play() != true {
                player = nil
                _ = startLoop()
            }
        } else {
            player?.pause()
        }
    }

    /// The same, taken on the spot rather than off the main actor: for an
    /// owner whose next step may be another player taking the session, which
    /// a configuration still in flight would then overwrite.
    @discardableResult
    func startNow() -> Bool {
        guard !isHeld else { return true }
        guard Self.activate(options: options), startLoop() else { return false }
        observeInterruptions()
        isHeld = true
        isPlaying = true
        return true
    }

    /// `deactivating: false` leaves the session active for whoever takes it
    /// next (the on-device player's stream run), which a deactivation still
    /// on its way would otherwise cut off.
    func stop(deactivating: Bool = true) {
        guard isHeld else { return }
        isHeld = false
        isPlaying = false
        player?.stop()
        player = nil
        playerSampleRate = nil
        for task in interruptionTasks { task.cancel() }
        interruptionTasks.removeAll()
        guard deactivating else { return }
        // Off the main actor for the same reason as activation, and nothing is
        // waiting on the result.
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    /// Re-takes the session after something else borrowed it — a song preview
    /// that ducked and then deactivated, an interruption that ended, a media
    /// services reset. Restores the category too: a borrower may have left
    /// `.duckOthers` behind, which forfeits the Now Playing claim.
    func reclaim() async {
        guard isHeld else { return }
        _ = await Self.configureSession(options: options)
        // Given up while the session was being configured — a car
        // unplugged, which is a route change too. A loop started from here
        // would play on with nothing to stop it.
        guard isHeld else { return }

        // A new route can bring a new hardware rate with it — Bluetooth
        // especially — and keeping a buffer built for the old one re-introduces
        // the converter `startLoop` exists to avoid. Cheap to check, and this
        // path already rebuilds the player for other reasons.
        let rate = AVAudioSession.sharedInstance().sampleRate
        if rate > 0, playerSampleRate != Int(rate) {
            player?.stop()
            player = nil
        }

        if player?.play() != true {
            player = nil
            _ = startLoop()
        }
        // Play first even when the transport is paused: the card is re-created
        // off audio actually starting, and pausing straight back is how a music
        // app returns to a paused card after an interruption.
        if !isPlaying { player?.pause() }
        onRestored?()
    }

    // MARK: - Session

    /// `.playback` with no options for the Sonos mirror, on purpose:
    /// `.mixWithOthers` and `.duckOthers` both let other audio keep the Now
    /// Playing claim, which is the one thing it exists to hold. `CarAudioClaim`
    /// takes `.mixWithOthers` all the same: the audio it sits beside is the
    /// app's own, played by another process, and stopping that would be
    /// worse than any claim.
    ///
    /// The I/O buffer is asked to be as long as the system will allow. This
    /// session is the app's one *continuous* background cost — it renders for as
    /// long as the speaker plays, with the app off screen — and that cost is a
    /// per-callback overhead multiplied by `sampleRate / bufferFrames`. At the
    /// `.playback` default of ~23 ms that is ~43 wake-ups a second to hand the
    /// system a buffer of zeroes; at ~100 ms it is ~10. iOS clamps the request
    /// to what the route supports, so this asks high and takes what it gets, and
    /// the added latency is meaningless for silence. Nothing else in the app
    /// cares either: the only other player is a song preview, where 100 ms to
    /// first sample is imperceptible.
    private static func configureSession(options: AVAudioSession.CategoryOptions) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            SilentAudioSession.activate(options: options)
        }.value
    }

    /// The configuration itself, on whatever thread calls it.
    nonisolated private static func activate(options: AVAudioSession.CategoryOptions) -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: options)
            // Preferred values are requests, and have to be made before
            // activation to be considered. A refusal is not a failure —
            // it only means the default buffer stands.
            try? session.setPreferredIOBufferDuration(0.1)
            try session.setActive(true)
            return true
        } catch {
            logger.error("Audio session failed to activate: \(error.localizedDescription)")
            return false
        }
    }

    private func startLoop() -> Bool {
        // Built at the route's own rate. A file that disagrees with the hardware
        // puts a sample-rate converter in the render path for the whole session
        // — 44.1 kHz against the 48 kHz every current iPhone runs — and it would
        // be resampling silence into silence. Only readable once the session is
        // active, which it is by the time this runs.
        let rate = AVAudioSession.sharedInstance().sampleRate
        let sampleRate = rate > 0 ? Int(rate) : 44_100

        do {
            let player = try AVAudioPlayer(
                data: Self.silentLoopWAV(sampleRate: sampleRate),
                fileTypeHint: AVFileType.wav.rawValue
            )
            player.numberOfLoops = -1
            player.volume = 0
            guard player.play() else { return false }
            self.player = player
            self.playerSampleRate = sampleRate
            return true
        } catch {
            logger.error("Silent loop failed to start: \(error.localizedDescription)")
            return false
        }
    }

    /// A phone call, Siri, or another app grabbing output suspends the loop, and
    /// without resuming it the claim — and so the card — quietly disappears. A
    /// media services reset invalidates the player object outright, and a route
    /// change stops it without any interruption being posted at all.
    ///
    /// None of this touches what the speakers are playing. The audio is on the
    /// network; the loop only exists to hold the card.
    private func observeInterruptions() {
        let center = NotificationCenter.default

        interruptionTasks = [
            Task { [weak self] in
                for await notification in center.notifications(named: AVAudioSession.interruptionNotification) {
                    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          AVAudioSession.InterruptionType(rawValue: raw) == .ended else { continue }
                    await self?.reclaim()
                }
            },
            // Unplugging headphones or dropping a Bluetooth route is a route
            // change, not an interruption, so none of the above fires — and iOS
            // stops the player on `.oldDeviceUnavailable` rather than moving it
            // to the speaker. Nothing audible is lost (there is no audio), but
            // the claim goes with it: silently, and now that a stopped loop means
            // a paused card, visibly wrong. Cheap and safe either way — if the
            // player survived the route change this is a no-op.
            Task { [weak self] in
                for await notification in center.notifications(named: AVAudioSession.routeChangeNotification) {
                    guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                          AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { continue }
                    guard let self, self.isHeld, self.isPlaying, self.player?.isPlaying != true else { continue }
                    await self.reclaim()
                }
            },
            Task { [weak self] in
                for await _ in center.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
                    guard let self, self.isHeld else { continue }
                    // The player object doesn't survive a reset.
                    self.player = nil
                    await self.reclaim()
                }
            },
        ]
    }

    // MARK: - Silence

    /// One second of mono PCM silence with a WAV header, built in memory — no
    /// bundled asset to keep in sync across targets.
    ///
    /// Cached by rate rather than built per activation. There is only ever one
    /// rate in play (the route's), so the cache holds one entry; it's keyed
    /// anyway because a route change can legitimately move it.
    private static var cachedLoops: [Int: Data] = [:]

    private static func silentLoopWAV(sampleRate: Int) -> Data {
        if let cached = cachedLoops[sampleRate] { return cached }
        let data = makeSilentPCMWAV(seconds: 1, sampleRate: sampleRate)
        cachedLoops[sampleRate] = data
        return data
    }

    private static func makeSilentPCMWAV(seconds: Double, sampleRate: Int) -> Data {
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
}
#endif

/// Silence the on-device player plays, mixed with others, while an Apple
/// Music run plays to a car (`LocalPlaybackService.syncCarAudio`).
///
/// MusicKit's player makes the sound in a process of its own, so this one
/// makes none, and iOS treats it accordingly: once the phone locks it is
/// suspended within seconds, and the card it keeps for the car
/// (`LocalNowPlayingPresenter`) stops there, the song and the clock with it,
/// with the car's play button reading paused all along — the car's Now
/// Playing screen goes by whether the card's own process is making sound.
/// Playing silence, paused and resumed with the music, keeps Cue running in
/// the background so the card follows the music, and stands to make the
/// car's button read playing.
///
/// Mixed with others because the music beside it isn't this process's:
/// MusicKit's player has its own audio session, and taking a session that
/// doesn't mix interrupts it — the music would stop the moment this began.
/// A mixable session also starts with Cue in the background, where a
/// non-mixable one is refused.
///
/// A type on every platform, empty off the iPhone, so the player that owns
/// it needs no platform checks of its own.
@MainActor
final class CarAudioClaim {
    #if os(iOS) && !targetEnvironment(macCatalyst)
    private let session = SilentAudioSession(options: [.mixWithOthers])
    /// No new attempt before this after one was refused: the caller asks on
    /// every poll, twice a second.
    private var retryAfter = Date.distantPast
    private let log = Logger(subsystem: "dance.cue", category: "nowplaying")
    #endif

    var isHeld: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return session.isHeld
        #else
        return false
        #endif
    }

    /// Takes the session if it isn't held, and plays or pauses the silence
    /// with the music.
    func hold(playing: Bool) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if !session.isHeld {
            guard Date.now >= retryAfter else { return }
            guard session.startNow() else {
                retryAfter = .now.addingTimeInterval(30)
                log.error("car audio: the session was refused")
                return
            }
            log.notice("car audio: held")
        }
        session.setPlaying(playing)
        #endif
    }

    /// Gives the session up. `deactivating: false` when a stream run of the
    /// player's own takes it straight over.
    func release(deactivating: Bool) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard session.isHeld else { return }
        session.stop(deactivating: false)
        if deactivating {
            // Here and now, as the player's own release is, rather than off
            // the main actor: a deactivation still on its way could land
            // after the next Apple run has taken the session again.
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        retryAfter = .distantPast
        log.notice("car audio: released")
        #endif
    }
}
