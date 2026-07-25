#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import Foundation

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
    private var observers: [NSObjectProtocol] = []

    private(set) var isHeld = false

    // MARK: - Lifecycle

    /// Takes the session. Returns false if the system refused it, in which case
    /// nothing is held and the caller should not proceed.
    @discardableResult
    func start() -> Bool {
        guard !isHeld else { return true }
        guard configureSession(), startLoop() else { return false }
        observeInterruptions()
        isHeld = true
        return true
    }

    func stop() {
        guard isHeld else { return }
        isHeld = false
        player?.stop()
        player = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Re-takes the session after something else borrowed it — a song preview
    /// that ducked and then deactivated, an interruption that ended, a media
    /// services reset. Restores the category too: a borrower may have left
    /// `.duckOthers` behind, which forfeits the Now Playing claim.
    func reclaim() {
        guard isHeld else { return }
        _ = configureSession()
        if player?.play() != true {
            player = nil
            _ = startLoop()
        }
        onRestored?()
    }

    // MARK: - Session

    /// `.playback` with no options on purpose: `.mixWithOthers` and
    /// `.duckOthers` both let other audio keep the Now Playing claim, which is
    /// the one thing this exists to hold.
    private func configureSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            return true
        } catch {
            print("Silent audio session failed to activate: \(error.localizedDescription)")
            return false
        }
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
            print("Silent audio loop failed: \(error.localizedDescription)")
            return false
        }
    }

    /// A phone call, Siri, or another app grabbing output suspends the loop, and
    /// without resuming it the claim — and so the card — quietly disappears. A
    /// media services reset invalidates the player object outright.
    private func observeInterruptions() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            MainActor.assumeIsolated { self?.reclaim() }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isHeld else { return }
                self.player = nil
                self.reclaim()
            }
        })
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
