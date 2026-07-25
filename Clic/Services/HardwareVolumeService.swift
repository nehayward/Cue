#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import MediaPlayer
import Observation
import SonosKit
import UIKit

@MainActor
@Observable
final class HardwareVolumeService {
    static let shared = HardwareVolumeService()

    /// Who the bridge is currently working for.
    ///
    /// Only one owner at a time: both would be writing the same system volume.
    /// The service arbitrates rather than the callers, so the player screen's
    /// modifier doesn't have to know which other features exist — it claims,
    /// and is refused if something with a longer life already holds it.
    enum Owner {
        /// The player screen, for as long as it's on screen.
        case playerScreen
        /// A background session that outlives any view. Outranks `playerScreen`.
        case session
    }

    /// How phone volume maps onto group volume.
    enum Mode {
        /// Any change in phone volume is one step up or down on the group, and
        /// the system slider is shoved back to a midpoint near the ends to keep
        /// headroom. Fine for hardware buttons: the phone's volume is a scratch
        /// value, not a reading.
        case relativeSteps
        /// The phone's volume *is* the group's volume, scaled — mirrored onto
        /// the slider, and sent back as a level. Needed wherever the slider is
        /// visible (the Lock Screen), where a scratch value would sit at a
        /// meaningless position, read a drag as one step, and stop responding
        /// once pinned at either end.
        case absoluteMirror
    }

    /// Observed, so a view that stood down while something else held the bridge
    /// re-runs and takes it back when the claim is released.
    private(set) var owner: Owner?

    @ObservationIgnored private var group: GroupRoom?
    @ObservationIgnored private var sonosService: SonosService?
    @ObservationIgnored private var volumeView: MPVolumeView?
    /// Resolved once per attach: reading it walks `subviews` and allocates.
    @ObservationIgnored private var slider: UISlider?
    @ObservationIgnored private var savedVolume: Float?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var mode: Mode = .relativeSteps
    /// False when someone else holds the audio session — it configures the
    /// category, and re-configuring it here would drop their claim. Also keeps
    /// the KVO alive while backgrounded, which is when a visible slider is used.
    @ObservationIgnored private var configuresAudioSession = true
    /// The last value written to the slider, to tell our own echo from a real
    /// change. Absolute mode can't use the relative mode's value-based filter,
    /// which only works because its writes always land on `restorePoint`.
    @ObservationIgnored private var lastWrittenSystemVolume: Float?
    @ObservationIgnored private var pendingGroupVolume: Int?
    @ObservationIgnored private var volumeSendTask: Task<Void, Never>?

    // Fixed midpoint gives room for both up and down on any starting volume.
    @ObservationIgnored private let restorePoint: Float = 0.5
    // Reset to midpoint when we're near an extreme to prevent getting stuck.
    @ObservationIgnored private let extremeThreshold: Float = 0.15
    // Single-point steps for fine-grained volume control.
    @ObservationIgnored private let volumeStep = 1

    private init() {}

    // MARK: - Public

    /// Claims the bridge for `owner`. Refused — a no-op — while a
    /// longer-lived owner holds it, so the caller doesn't have to know what else
    /// exists.
    @discardableResult
    func start(
        group: GroupRoom,
        sonosService: SonosService,
        volumeView: MPVolumeView,
        as owner: Owner = .playerScreen,
        mode: Mode = .relativeSteps,
        configuresAudioSession: Bool = true
    ) -> Bool {
        if let current = self.owner, current == .session, owner != .session { return false }

        self.group = group
        self.sonosService = sonosService
        self.volumeView = volumeView
        self.slider = volumeView.subviews.compactMap { $0 as? UISlider }.first
        self.mode = mode
        self.configuresAudioSession = configuresAudioSession
        self.owner = owner
        // Snapshot once so stop() can restore it; don't clobber across restarts.
        if savedVolume == nil {
            savedVolume = AVAudioSession.sharedInstance().outputVolume
        }
        restart()
        syncSystemVolume()
        return true
    }

    /// Mirrors the group's volume onto the phone's slider. No-op outside
    /// absolute mode.
    ///
    /// Called whenever the group's volume changes from any source — a press on
    /// the speaker, the Sonos app, another Clic surface — so a visible slider
    /// reads the speaker's actual level rather than a leftover phone value.
    func syncSystemVolume() {
        guard mode == .absoluteMirror, let group, let slider else { return }
        let target = Float(max(0, min(100, group.groupVolume)) / 100)
        // Already there (within a slider step) — writing again would only
        // generate an echo to filter.
        guard abs(slider.value - target) > 0.005 else { return }
        lastWrittenSystemVolume = target
        slider.setValue(target, animated: false)
    }

    /// Releases the claim. Ignored when someone else holds it, so a view tearing
    /// down can't stop a session it never owned.
    func stop(as owner: Owner = .playerScreen) {
        guard self.owner == owner else { return }

        task?.cancel()
        task = nil
        volumeSendTask?.cancel()
        volumeSendTask = nil
        pendingGroupVolume = nil
        lastWrittenSystemVolume = nil
        if let saved = savedVolume {
            slider?.setValue(saved, animated: false)
        }
        savedVolume = nil
        group = nil
        sonosService = nil
        volumeView = nil
        slider = nil
        if configuresAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        configuresAudioSession = true
        mode = .relativeSteps
        self.owner = nil
    }

    // MARK: - Private

    private func restart() {
        task?.cancel()
        // A session owner outlives the foreground — the app stays alive on the
        // audio background mode — and backgrounded is exactly when a visible
        // slider is used, so listen straight through rather than per foreground.
        guard owner != .session else {
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
        if configuresAudioSession {
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

                if self.mode == .absoluteMirror {
                    // Our own `syncSystemVolume` write coming back around.
                    if let written = self.lastWrittenSystemVolume, abs(new - written) < 0.005 { return }
                    let volume = Int((new * 100).rounded())
                    // The codebase's convention for an in-progress volume
                    // gesture (`VolumeControlView`, `RoomVolumeView`): the poll
                    // checks it before overwriting `groupVolume`, so without it a
                    // foreground drag gets clobbered mid-gesture by a stale
                    // reading — and `syncSystemVolume` then shoves the slider
                    // back under the user's finger.
                    group.isEditingVolume = true
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

        if mode == .absoluteMirror {
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
            // Gesture over: hand `groupVolume` back to the poll.
            self?.group?.isEditingVolume = false
            self?.volumeSendTask = nil
        }
    }
}
#endif
