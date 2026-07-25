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
    /// False when the Now Playing session owns the audio session. It holds
    /// `.playback` to keep the Lock Screen card up; re-configuring the session
    /// to `.ambient` here would drop that claim. Also keeps the KVO alive while
    /// backgrounded, since that's exactly when the Lock Screen slider is used.
    private var ownsAudioSession = true

    /// Absolute mode, used by the Now Playing session.
    ///
    /// The default (player screen) mode is *relative*: any change in the phone's
    /// output volume is read as one step up or down on the group, and the system
    /// slider is shoved back to a midpoint whenever it nears an end so there's
    /// always headroom for the next press. That works for hardware buttons, but
    /// it means the phone's volume is a scratch value with no relationship to the
    /// speaker — so the Lock Screen's slider sits wherever it happens to be, a
    /// drag registers as a single step, and once it pins at 0 or 1 the presses
    /// stop doing anything.
    ///
    /// In absolute mode the phone's volume *is* the group's volume, scaled: the
    /// group's level is mirrored onto the system slider, and any change the user
    /// makes is sent to the group as a level rather than a nudge. No midpoint
    /// reset, no ends to hit.
    private var mirrorsGroupVolume = false
    /// The last value written to the slider, to tell our own echo from a real
    /// change. Absolute mode can't use the default's value-based filter, which
    /// only works because its writes always land on `restorePoint`.
    private var lastWrittenSystemVolume: Float?
    private var pendingGroupVolume: Int?
    private var volumeSendTask: Task<Void, Never>?

    // Fixed midpoint gives room for both up and down on any starting volume.
    private let restorePoint: Float = 0.5
    // Reset to midpoint when we're near an extreme to prevent getting stuck.
    private let extremeThreshold: Float = 0.15
    // Single-point steps for fine-grained volume control.
    private let volumeStep = 1

    private var slider: UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    private init() {}

    // MARK: - Public

    func start(
        group: GroupRoom,
        sonosService: SonosService,
        volumeView: MPVolumeView,
        ownsAudioSession: Bool = true
    ) {
        self.group = group
        self.sonosService = sonosService
        self.volumeView = volumeView
        self.ownsAudioSession = ownsAudioSession
        self.mirrorsGroupVolume = !ownsAudioSession
        // Snapshot once so stop() can restore it; don't clobber across restarts.
        if savedVolume == nil {
            savedVolume = AVAudioSession.sharedInstance().outputVolume
        }
        restart()
        syncSystemVolume()
    }

    /// Mirrors the group's volume onto the phone's slider. No-op outside
    /// absolute mode.
    ///
    /// Called whenever the group's volume changes from any source — a press on
    /// the speaker, the Sonos app, another Clic surface — so the Lock Screen
    /// slider reads the speaker's actual level rather than a leftover phone
    /// value.
    func syncSystemVolume() {
        guard mirrorsGroupVolume, let group, let slider else { return }
        let target = Float(max(0, min(100, group.groupVolume)) / 100)
        // Already there (within a slider step) — writing again would only
        // generate an echo to filter.
        guard abs(slider.value - target) > 0.005 else { return }
        lastWrittenSystemVolume = target
        slider.setValue(target, animated: false)
    }

    func stop() {
        task?.cancel()
        task = nil
        volumeSendTask?.cancel()
        volumeSendTask = nil
        pendingGroupVolume = nil
        lastWrittenSystemVolume = nil
        mirrorsGroupVolume = false
        if let saved = savedVolume {
            slider?.setValue(saved, animated: false)
        }
        savedVolume = nil
        group = nil
        sonosService = nil
        volumeView = nil
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        ownsAudioSession = true
    }

    // MARK: - Private

    private func restart() {
        task?.cancel()
        // Driven by the Now Playing session: the app keeps running on the audio
        // background mode, and the Lock Screen slider only exists while
        // backgrounded — so listen straight through instead of per foreground.
        guard ownsAudioSession else {
            task = Task { [weak self] in await self?.listen() }
            return
        }
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
        if ownsAudioSession {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }

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
                      abs(new - old) > 0.001 else { return }

                if self.mirrorsGroupVolume {
                    // Our own `syncSystemVolume` write coming back around.
                    if let written = self.lastWrittenSystemVolume, abs(new - written) < 0.005 { return }
                    let volume = Int((new * 100).rounded())
                    group.groupVolume = Double(volume)
                    self.sendGroupVolume(volume)
                    return
                }

                guard abs(new - self.restorePoint) > 0.02 else { return }
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

        if mirrorsGroupVolume {
            // Absolute mode has no midpoint to hold — 0 and 1 are real positions,
            // meaning a silent and a full-volume speaker. Seed the slider from
            // the group instead.
            syncSystemVolume()
        } else {
            let initial = session.outputVolume
            if initial >= (1 - extremeThreshold) || initial <= extremeThreshold {
                slider?.setValue(restorePoint, animated: false)
            }
        }

        for await delta in stream {
            guard let group = self.group, let sonosService = self.sonosService else { break }
            let ip = group.ip
            Task { await sonosService.setRelativeGroupVolume(ip: ip, volume: delta) }
        }
    }

    /// Sends an absolute group volume, coalescing while one is in flight.
    ///
    /// A slider drag produces a KVO callback every few pixels. Firing a SOAP call
    /// per callback would queue dozens of requests behind each other and leave
    /// the speaker chasing the drag long after the finger lifted; only the latest
    /// value matters, so intermediates are dropped.
    private func sendGroupVolume(_ volume: Int) {
        pendingGroupVolume = volume
        guard volumeSendTask == nil else { return }
        volumeSendTask = Task { @MainActor [weak self] in
            while true {
                guard let self,
                      let next = self.pendingGroupVolume,
                      let ip = self.group?.ip,
                      let sonosService = self.sonosService else { break }
                self.pendingGroupVolume = nil
                await sonosService.setGroupVolume(ip: ip, volume: next)
            }
            self?.volumeSendTask = nil
        }
    }
}
#endif
