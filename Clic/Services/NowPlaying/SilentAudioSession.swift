#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import Foundation
import OSLog

/// Only failures are logged. Taking the session is the whole feature, so a
/// refusal is worth a breadcrumb; everything else is silent.
private let logger = Logger(subsystem: "com.clic", category: "NowPlaying")

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
@MainActor
final class SilentAudioSession {
    /// Called after the session has been re-established following something that
    /// interrupted it. The owner uses it to republish whatever state the
    /// interruption may have invalidated.
    var onRestored: (() -> Void)?

    private var player: AVAudioPlayer?
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
        guard await Self.configureSession(), startLoop() else { return false }
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

    func stop() {
        guard isHeld else { return }
        isHeld = false
        isPlaying = false
        player?.stop()
        player = nil
        for task in interruptionTasks { task.cancel() }
        interruptionTasks.removeAll()
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
        _ = await Self.configureSession()
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

    /// `.playback` with no options on purpose: `.mixWithOthers` and
    /// `.duckOthers` both let other audio keep the Now Playing claim, which is
    /// the one thing this exists to hold.
    private static func configureSession() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                return true
            } catch {
                logger.error("Audio session failed to activate: \(error.localizedDescription)")
                return false
            }
        }.value
    }

    private func startLoop() -> Bool {
        do {
            let player = try AVAudioPlayer(data: Self.silentLoopWAV, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            player.volume = 0
            guard player.play() else { return false }
            self.player = player
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

    /// One second of 44.1 kHz mono PCM silence with a WAV header, built in
    /// memory — no bundled asset to keep in sync across targets, and built once
    /// rather than per activation.
    private static let silentLoopWAV: Data = makeSilentPCMWAV(seconds: 1)

    private static func makeSilentPCMWAV(seconds: Double) -> Data {
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
}
#endif
