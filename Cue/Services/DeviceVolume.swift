import AVFoundation
import Defaults
import MediaPlayer
import SwiftUI

/// The volume behind the local player's slider.
///
/// On iPhone and iPad that is the device's own volume — the level the
/// hardware buttons move and the Lock Screen shows — read through the audio
/// session and written through a hidden `MPVolumeView`, the only sanctioned
/// way to set it. Mac Catalyst has no such view, so there the slider is the
/// app's own output level applied to the stream player, the way a Mac music
/// app's slider works, and it's kept across launches.
///
/// Kept off while `HardwareVolumeService` holds the system volume for a
/// Sonos group: a write from here would arrive there looking like a button
/// press and move the speakers instead of the phone.
@MainActor
@Observable
final class DeviceVolume {
    static let shared = DeviceVolume()

#if os(iOS) && !targetEnvironment(macCatalyst)
    /// The device volume, 0...1. Follows the hardware buttons.
    private(set) var level: Double = Double(AVAudioSession.sharedInstance().outputVolume)

    var isAvailable: Bool { HardwareVolumeService.shared.owner == nil }

    @ObservationIgnored private var volumeView: MPVolumeView?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var systemVolumeObserver: NSObjectProtocol?
    /// The level a drag last asked for, not yet handed to the system.
    @ObservationIgnored private var pendingSystemLevel: Float?
    @ObservationIgnored private var lastSystemLevel: Float?
    /// The one write loop to the hidden slider, while it runs.
    @ObservationIgnored private var systemWriteTask: Task<Void, Never>?
    /// The most the system volume is written per second during a drag.
    private static let systemWriteInterval: Duration = .milliseconds(33)

    private init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let new = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.update(Double(new))
            }
        }
        // The KVO above only fires while this app's audio session is active —
        // with nothing playing (a relaunch, a paused queue) the hardware
        // buttons moved the volume and the slider never heard. The system
        // posts this on every change, active session or not.
        systemVolumeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("SystemVolumeDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Only a real change. A route change posts here too, always
            // with a volume of 0 whatever the level is, which dropped the
            // slider to zero.
            guard note.userInfo?["Reason"] as? String == "ExplicitVolumeChange",
                  let volume = note.userInfo?["Volume"] as? Float else { return }
            MainActor.assumeIsolated { self?.update(Double(volume)) }
        }
    }

    /// Takes a level the system reported. Skipped while a drag is being
    /// written, so the system's stepped echo can't pull the slider back
    /// under the finger.
    private func update(_ value: Double) {
        guard systemWriteTask == nil else { return }
        // `@Observable` notifies on every write, equal or not.
        guard level != value else { return }
        level = value
    }

    func set(_ value: Double) {
        guard isAvailable else { return }
        let clamped = Float(max(0, min(1, value)))
        // Shown immediately; the session's own change comes back through
        // the observation a moment later at the nearest system step.
        if level != Double(clamped) { level = Double(clamped) }

        // A drag calls this for every pointer move, and each write to the
        // hidden slider is a synchronous round trip to the media server that
        // also redraws the system volume HUD — done per tick, it held up the
        // main thread and the slider stuttered behind the finger. Write at
        // most ~30 times a second, always the latest level, never a repeat.
        pendingSystemLevel = clamped
        guard systemWriteTask == nil else { return }
        systemWriteTask = Task { [weak self] in
            while true {
                guard let self, let next = self.pendingSystemLevel else { break }
                self.pendingSystemLevel = nil
                guard next != self.lastSystemLevel else { continue }
                self.lastSystemLevel = next
                self.writeSystem(next)
                try? await Task.sleep(for: Self.systemWriteInterval)
            }
            // Forget the last level once idle: the hardware buttons may have
            // moved the volume since, and the next drag must not skip it.
            self?.lastSystemLevel = nil
            self?.systemWriteTask = nil
            self?.scheduleDetach()
        }
    }

    @ObservationIgnored private var detachTask: Task<Void, Never>?

    /// Takes the hidden slider back out of the window a moment after the
    /// last write. Left parked, it hid the system volume HUD everywhere in
    /// the app, long after the player that used it had closed — iOS skips
    /// the HUD while any `MPVolumeView` is in a window. The player keeps its
    /// own for as long as it is on screen.
    private func scheduleDetach() {
        detachTask?.cancel()
        detachTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.systemWriteTask == nil else { return }
            self.volumeView?.removeFromSuperview()
            self.volumeView = nil
        }
    }

    private func writeSystem(_ value: Float) {
        detachTask?.cancel()
        attach()
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(value, animated: false)
        slider.sendActions(for: .touchUpInside)
    }

    /// Parks the hidden slider in a window: it has no `UISlider` until it is
    /// in a hierarchy, and a scene that went away takes it along.
    private func attach() {
        if let volumeView, volumeView.window != nil { return }
        volumeView?.removeFromSuperview()
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.alpha = 0.0001
        view.isUserInteractionEnabled = false
        window.addSubview(view)
        volumeView = view
    }
#else
    /// The app's output level, 0...1.
    private(set) var level: Double

    /// Apple Music plays in the system's own player, which has no per-app
    /// level to set — the slider only means something for a stream run.
    var isAvailable: Bool { LocalPlaybackService.shared.isPlayingLocalStream }

    private init() {
        let stored = UserDefaults.standard.object(forKey: AppStorageKeys.localPlaybackVolume) as? Double
        level = stored ?? 1
        LocalPlaybackService.shared.streamVolume = Float(level)
    }

    func set(_ value: Double) {
        let clamped = max(0, min(1, value))
        // A drag calls this for every pointer move, most of them at the same
        // level; an `@Observable` write notifies even when nothing changed.
        guard clamped != level else { return }
        level = clamped
        UserDefaults.standard.set(level, forKey: AppStorageKeys.localPlaybackVolume)
        LocalPlaybackService.shared.streamVolume = Float(level)
    }
#endif
}
