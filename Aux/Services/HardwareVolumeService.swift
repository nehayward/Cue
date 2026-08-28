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

    /// The mirrored target, held as the coordinator's id and resolved against
    /// `SonosService` at time of use. Topology changes replace `GroupRoom`
    /// instances, and a bridge that kept one went on mirroring — and measuring
    /// the next press against — an orphan whose volume never moves again.
    /// Resolving late means there is nothing to re-point; while the id has no
    /// group (mid-regroup, or a coordinator that was absorbed) the bridge is
    /// simply inert until the model catches up.
    @ObservationIgnored private var groupID: String?
    @ObservationIgnored private var sonosService: SonosService?
    private var group: GroupRoom? {
        guard let groupID else { return nil }
        return sonosService?.groups.first(where: { $0.coordinatorID == groupID })
    }
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
    /// The last few values written to the slider, oldest first, to tell our own
    /// echoes from a real change. Absolute mode can't use the relative mode's
    /// value-based filter, which only works because its writes always land on
    /// `restorePoint`. Remembering just the last write wasn't enough either:
    /// writes land in bursts around a regroup — the group's average moves, then
    /// moves again — and the echo of the first write compared against the
    /// memory of the second read as the user's hand, which sent the group an
    /// absolute level off a slider that was mid-correction.
    @ObservationIgnored private var recentSystemVolumeWrites: [Float] = []
    @ObservationIgnored private var pendingGroupVolume: Int?
    @ObservationIgnored private var volumeSendTask: Task<Void, Never>?
    /// Holds `isEditingVolume` through a hardware press (and a held button's
    /// stream of them), then hands `groupVolume` back to the poll.
    @ObservationIgnored private var pressEditingTask: Task<Void, Never>?
    /// True while the device's audio is routed off the phone — see
    /// `AudioOutputRoute.isExternal`. The bridge stays claimed and goes inert:
    /// on that route the phone's volume is the *other* device's volume, in both
    /// directions, so neither reading it nor writing it is ours to do.
    @ObservationIgnored private var isSuspended = false
    /// True for a moment after a route change, while the system restores the
    /// new route's remembered level.
    @ObservationIgnored private var isSettling = false
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// The system volume is quantised to 16 steps, and everything about
    /// absolute mode's echo filtering follows from that.
    ///
    /// `syncSystemVolume` writes a group level scaled to 0…1 — an arbitrary
    /// value — and the system snaps it to the nearest step, so what comes back
    /// through the KVO is up to *half a step* away from what we wrote. The
    /// filter that had to recognise that echo allowed 0.005, which is a sixth of
    /// the worst case, so most of our own writes were read as the user having
    /// moved the volume: each one sent a real `setGroupVolume` to the speaker
    /// (pulling the group's level onto the phone's 16-point grid, off by a point
    /// or two), and the speaker's echo of *that* came back through the socket as
    /// another model write. All of it while backgrounded, where the card is the
    /// only thing driving anything.
    ///
    /// Half a step is the exact boundary: a genuine button press is a whole step
    /// from the current position, so it is never closer than half a step to the
    /// value we wrote, and nothing real gets swallowed.
    @ObservationIgnored private let systemVolumeStep: Float = 1.0 / 16.0

    // Fixed midpoint gives room for both up and down on any starting volume.
    @ObservationIgnored private let restorePoint: Float = 0.5
    // Reset to midpoint when we're near an extreme to prevent getting stuck.
    @ObservationIgnored private let extremeThreshold: Float = 0.15
    // Single-point steps for fine-grained volume control.
    @ObservationIgnored private let volumeStep = 1
    /// The largest single jump in system volume that could have come from a
    /// gesture: four `systemVolumeStep`s. A hardware press moves exactly one
    /// step and a slider drag arrives as a stream of small changes, so nothing
    /// a hand can do lands four steps away in one callback — anything that does
    /// was set programmatically. Four rather than two so a coarse or dropped
    /// drag still gets through. See the refusal in `listen()`.
    @ObservationIgnored private let maxGestureStep: Float = 4.0 / 16.0
    /// How long to swallow `outputVolume` changes after a route change. The
    /// restored level doesn't arrive with the notification — it lands a beat
    /// later, as a change indistinguishable from a button press.
    @ObservationIgnored private let routeSettleDelay: Duration = .milliseconds(1500)

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

        self.groupID = group.coordinatorID
        self.sonosService = sonosService
        self.volumeView = volumeView
        self.slider = volumeView.subviews.compactMap { $0 as? UISlider }.first
        self.mode = mode
        self.configuresAudioSession = configuresAudioSession
        self.owner = owner
        self.isSuspended = AudioOutputRoute.isExternal
        // A fresh attach is a fresh conversation with the slider: entries from
        // the previous one have no echo coming and would only swallow a real
        // press that happens to land near them.
        self.recentSystemVolumeWrites = []
        // Snapshot once so stop() can restore it; don't clobber across restarts.
        if savedVolume == nil {
            savedVolume = AVAudioSession.sharedInstance().outputVolume
        }
        observeRouteChanges()
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
        // Not onto a car stereo or a pair of headphones. Suspended, the phone's
        // volume is audible and belongs to that device; pushing the group's
        // level onto it would set someone's car to whatever the speakers at
        // home happen to be at.
        guard !isSuspended, mode == .absoluteMirror, let group, let slider else { return }
        let target = Float(max(0, min(100, group.groupVolume)) / 100)
        // Already there — writing again would only generate an echo to filter.
        // Measured against half a system step rather than an arbitrary epsilon:
        // inside that, `target` snaps to the step the slider is already on, so
        // the write cannot move anything. The old 0.005 wrote on group changes
        // too small for a 16-step slider to represent at all.
        guard abs(slider.value - target) > systemVolumeStep / 2 else { return }
        recentSystemVolumeWrites.append(target)
        // Deeper than any realistic burst of un-echoed writes. Entries are
        // consumed as their echoes arrive; the cap only sheds leftovers from
        // writes whose echo never came.
        if recentSystemVolumeWrites.count > 4 {
            recentSystemVolumeWrites.removeFirst(recentSystemVolumeWrites.count - 4)
        }
        slider.setValue(target, animated: false)
    }

    /// Releases the claim. Ignored when someone else holds it, so a view tearing
    /// down can't stop a session it never owned.
    func stop(as owner: Owner = .playerScreen) {
        guard self.owner == owner else { return }

        task?.cancel()
        task = nil
        routeTask?.cancel()
        routeTask = nil
        settleTask?.cancel()
        settleTask = nil
        isSuspended = false
        isSettling = false
        volumeSendTask?.cancel()
        volumeSendTask = nil
        pendingGroupVolume = nil
        pressEditingTask?.cancel()
        pressEditingTask = nil
        recentSystemVolumeWrites = []
        // `savedVolume` is cleared on a route change, so this can only ever
        // restore a level onto the route it was taken from.
        if let saved = savedVolume {
            slider?.setValue(saved, animated: false)
        }
        savedVolume = nil
        groupID = nil
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

    // MARK: - Routing

    /// Watches where the device's audio is going, for as long as the bridge is
    /// claimed. Cancelled by `stop()`.
    private func observeRouteChanges() {
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                self?.handleRouteChange()
            }
        }
    }

    /// A route change moves the phone's volume on its own, without anybody
    /// touching anything: iOS remembers a level per route and restores it on
    /// connect. Passing that on would hand the speakers whatever the car stereo
    /// was last set to — which is exactly how a Sonos group ends up at 100%
    /// because a phone got into a car.
    ///
    /// So the bridge goes quiet across the change and comes back by *writing*
    /// the group's level out rather than reading the phone's in.
    private func handleRouteChange() {
        // Captured on the route we're leaving. Restoring it onto the new one in
        // `stop()` would set some other device's volume to a level that was
        // never its own.
        savedVolume = nil
        isSuspended = AudioOutputRoute.isExternal
        beginSettling()
    }

    /// Swallows `outputVolume` changes for a moment, then re-seeds the phone
    /// from the group.
    private func beginSettling() {
        isSettling = true
        // Echoes of writes made before the route moved are dropped by the
        // settling guard, so their entries would linger and swallow a real
        // press later. The post-settle re-seed records a fresh one.
        recentSystemVolumeWrites = []
        settleTask?.cancel()
        let delay = routeSettleDelay
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.isSettling = false
            self.settleTask = nil
            // Re-take the new route's level as the one to put back, now that
            // the system has finished restoring it.
            if self.owner != nil {
                self.savedVolume = AVAudioSession.sharedInstance().outputVolume
            }
            // `syncSystemVolume` is a no-op while suspended, which is what we
            // want: on an external route the phone keeps its own level.
            self.syncSystemVolume()
        }
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
                      let new = change.newValue,
                      let old = change.oldValue,
                      abs(new - old) > 0.001 else { return }

                // Not ours to read: the audio is on a car stereo, a headset or
                // an AirPlay device, whose volume this is — or the route just
                // moved and the system is restoring that route's remembered
                // level, which arrives here looking exactly like a button press.
                guard !self.isSuspended, !self.isSettling else { return }

                // One of our own `syncSystemVolume` writes coming back around,
                // snapped to the nearest system step. Echoes arrive in write
                // order, so a match also retires everything older than it.
                // Consumed ahead of resolving the group: an echo landing while
                // the id briefly resolves to nothing (mid-regroup) still has to
                // be retired, or the stale entry swallows a later real press.
                // See `systemVolumeStep`.
                if self.mode == .absoluteMirror,
                   let match = self.recentSystemVolumeWrites.firstIndex(where: {
                       abs(new - $0) < self.systemVolumeStep / 2
                   }) {
                    self.recentSystemVolumeWrites.removeSubrange(...match)
                    return
                }

                // Transiently nothing to steer — the target is mid-regroup, or
                // was absorbed into another group. Drop the change; the bridge
                // comes back the moment the id resolves again.
                guard let group = self.group else { return }

                if self.mode == .absoluteMirror {
                    // A hardware button press: the system volume moves exactly
                    // one of its 16 steps in a single change — a drag arrives
                    // as pixel-sized changes and can't match. Mapped through
                    // the absolute scale a press was a ~6-point jump on the
                    // group; send it as the same single step the player
                    // screen's relative mode does, then put the slider back on
                    // the group's level so the next press is measured from the
                    // truth (that write is swallowed as an echo above). Ahead
                    // of the regroup absorb below on purpose: a relative step
                    // is safe whatever the topology is doing.
                    if let step = self.singleButtonStep(from: old, to: new) {
                        // The convention the poll and the socket handler check
                        // before overwriting `groupVolume` — without it a read
                        // already in flight lands with the pre-press level,
                        // and `syncSystemVolume` yanks the slider back to it.
                        group.isEditingVolume = true
                        group.groupVolume = max(0, min(100, group.groupVolume + Double(step)))
                        if let sonosService = self.sonosService {
                            let ip = group.ip
                            Task { await sonosService.setRelativeGroupVolume(ip: ip, volume: step) }
                        }
                        // Debounced so a held button keeps the hold alive; the
                        // 400 ms matches the local-command hold the poll
                        // already honours.
                        self.pressEditingTask?.cancel()
                        self.pressEditingTask = Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .milliseconds(400))
                            guard !Task.isCancelled else { return }
                            self?.group?.isEditingVolume = false
                        }
                        self.syncSystemVolume()
                        return
                    }

                    // While the app is regrouping, the group's reported volume
                    // moves for structural reasons — members joining or leaving
                    // shift the average — and the mirror is busy chasing it.
                    // Anything else arriving here is not a hand on the slider;
                    // adopting it would send the group an absolute level read
                    // off a slider that is mid-correction. Absorb it and keep
                    // the slider on the group instead.
                    if self.sonosService?.isGrouping == true {
                        self.syncSystemVolume()
                        return
                    }

                    // A single change this large is not a gesture. A hardware
                    // press moves the system volume exactly one step and a
                    // slider drag arrives as a stream of small changes, so
                    // nothing a hand can do lands four steps away in one
                    // callback — a jump that big was set programmatically: a
                    // Shortcuts automation, another app's `MPVolumeView`, an
                    // accessory, a route's remembered level. It hands the group
                    // that number in a single step, which is how a pair of Fives
                    // ends up at 100% with nobody in the house.
                    //
                    // Refusing it leaves the two out of step, so put the phone
                    // back where the group actually is. The echo filter above
                    // catches that write, so this can't recur.
                    if abs(new - old) > self.maxGestureStep {
                        self.syncSystemVolume()
                        return
                    }

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
            // the group instead. (No-op while suspended: the phone's volume
            // belongs to whatever it's plugged into.)
            syncSystemVolume()
        } else if !isSuspended {
            let initial = session.outputVolume
            if initial >= (1 - extremeThreshold) || initial <= extremeThreshold {
                slider?.setValue(restorePoint, animated: false)
            }
        }

        for await delta in stream {
            // The service is only gone after stop(), which also cancels this
            // task — ending the loop is just tidy. The group resolving to
            // nothing is different: it's transient (mid-regroup), so drop the
            // step and keep listening rather than tearing the bridge down.
            guard let sonosService = self.sonosService else { break }
            guard let group = self.group else { continue }
            let ip = group.ip
            Task { await sonosService.setRelativeGroupVolume(ip: ip, volume: delta) }
        }
    }

    /// The signature of a hardware button press while mirroring: the system
    /// volume moves by exactly one of its 16 steps in a single change. A
    /// slider drag arrives as a stream of pixel-sized changes, so a whole-step
    /// delta in one callback is a button — drags keep the absolute scale.
    ///
    /// Deliberately measured as a delta, not against the step boundaries: a
    /// drag can leave the system volume resting *between* boundaries, and
    /// anchoring the check to the grid made the first press after every drag
    /// fall through to the absolute path — the multi-point jump again, and
    /// persistently, since nothing moved the slider back onto the grid.
    private func singleButtonStep(from old: Float, to new: Float) -> Int? {
        // Well inside half a step: nothing but a button covers a whole step in
        // one callback.
        let tolerance: Float = 0.005
        guard abs(abs(new - old) - systemVolumeStep) < tolerance else { return nil }
        return new > old ? volumeStep : -volumeStep
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
