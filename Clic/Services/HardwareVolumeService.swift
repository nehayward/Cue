#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import MediaPlayer
import SonosKit
import UIKit

@MainActor
final class HardwareVolumeService {
    static let shared = HardwareVolumeService()

    private var group: GroupRoom?
    private var sonosService: SonosService?
    private var volumeView: MPVolumeView?
    private var savedVolume: Float?
    private var task: Task<Void, Never>?

    // Fixed midpoint gives room for both up and down on any starting volume.
    private let restorePoint: Float = 0.5
    // Reset to midpoint when we're near an extreme to prevent getting stuck.
    private let extremeThreshold: Float = 0.15
    // Two-point steps match the feel of native iOS volume increments.
    private let volumeStep = 2

    private var slider: UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    private init() {}

    // MARK: - Public

    func start(group: GroupRoom, sonosService: SonosService, volumeView: MPVolumeView) {
        self.group = group
        self.sonosService = sonosService
        self.volumeView = volumeView
        // Snapshot once so stop() can restore it; don't clobber across restarts.
        if savedVolume == nil {
            savedVolume = AVAudioSession.sharedInstance().outputVolume
        }
        restart()
    }

    func stop() {
        task?.cancel()
        task = nil
        if let saved = savedVolume {
            slider?.setValue(saved, animated: false)
        }
        savedVolume = nil
        group = nil
        sonosService = nil
        volumeView = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Temporarily stop capturing the hardware volume buttons without discarding
    /// configuration, so another audio-session owner (a song preview) can play
    /// and let the buttons control its own volume. Pairs with `resume()`. No-op
    /// if not currently running.
    func suspend() {
        task?.cancel()
        task = nil
    }

    /// Resume capturing after `suspend()`. Safe to call unconditionally: a no-op
    /// when the service was never started (nothing configured) or is already
    /// running.
    func resume() {
        guard volumeView != nil, task == nil else { return }
        restart()
    }

    // MARK: - Private

    private func restart() {
        task?.cancel()
        // [weak self] breaks the self → task → self reference cycle.
        task = Task { [weak self] in
            guard let self else { return }
            var listenTask: Task<Void, Never>? = Task { [weak self] in await self?.listen() }
            defer { listenTask?.cancel() }
            for await event in appEvents() {
                listenTask?.cancel()
                listenTask = event == .foreground ? Task { [weak self] in await self?.listen() } : nil
            }
        }
    }

    private enum AppEvent { case foreground, background }

    // Observers are removed automatically via `onTermination` when cancelled.
    private func appEvents() -> AsyncStream<AppEvent> {
        AsyncStream { continuation in
            let fg = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil, queue: .main
            ) { _ in continuation.yield(.foreground) }
            let bg = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil, queue: .main
            ) { _ in continuation.yield(.background) }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(fg)
                NotificationCenter.default.removeObserver(bg)
            }
        }
    }

    private func listen() async {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        // Brief delay lets AVAudioSession activation settle before we attach KVO.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        var continuation: AsyncStream<Int>.Continuation?
        let stream = AsyncStream<Int> { continuation = $0 }

        // KVO is the reliable path for hardware-button detection. Echo filter is
        // value-based: our resets always land at restorePoint; real presses land
        // ≥0.0625 away. No boolean flag needed, no timing risk.
        let observation = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                guard let self,
                      let group = self.group,
                      let new = change.newValue,
                      let old = change.oldValue,
                      abs(new - old) > 0.001,
                      abs(new - self.restorePoint) > 0.02 else { return }
                let delta = new > old ? self.volumeStep : -self.volumeStep
                group.groupVolume = max(0, min(100, group.groupVolume + Double(delta)))
                if new >= (1 - self.extremeThreshold) || new <= self.extremeThreshold {
                    self.slider?.setValue(self.restorePoint, animated: false)
                }
                continuation?.yield(delta)
            }
        }
        defer {
            observation.invalidate()
            continuation?.finish()
        }

        let initial = session.outputVolume
        if initial >= (1 - extremeThreshold) || initial <= extremeThreshold {
            slider?.setValue(restorePoint, animated: false)
        }

        for await delta in stream {
            guard let group = self.group, let sonosService = self.sonosService else { break }
            let ip = group.ip
            Task { await sonosService.setRelativeGroupVolume(ip: ip, volume: delta) }
        }
    }
}
#endif
