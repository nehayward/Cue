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

    private init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let new = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.level = Double(new)
            }
        }
    }

    func set(_ value: Double) {
        guard isAvailable else { return }
        let clamped = Float(max(0, min(1, value)))
        // Shown immediately; the session's own change comes back through
        // the observation a moment later at the nearest system step.
        level = Double(clamped)
        attach()
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(clamped, animated: false)
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
        level = max(0, min(1, value))
        UserDefaults.standard.set(level, forKey: AppStorageKeys.localPlaybackVolume)
        LocalPlaybackService.shared.streamVolume = Float(level)
    }
#endif
}
