#if os(iOS) && !targetEnvironment(macCatalyst)
import Defaults
import MediaPlayer
import SonosKit
import SubscriptionKit
import SwiftUI

private struct VolumeViewRepresentable: UIViewRepresentable {
    let view: MPVolumeView
    func makeUIView(context: Context) -> MPVolumeView { view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct HardwareVolumeControlModifier: ViewModifier {
    /// Nil leaves the buttons to this device's own volume.
    let group: GroupRoom?
    @Environment(SonosService.self) private var sonosService
    @Environment(FeatureGate.self) private var featureGate
    // Defaults to true — see `AppStorageKeys`. The literal has to match the
    // `UserDefaults` accessor the Lock Screen path reads
    // (`hardwareVolumeButtonsEnabled`); a disagreement would mean the buttons
    // controlled the group on one surface and the device on the other.
    @AppStorage(AppStorageKeys.useHardwareVolumeButtons) private var useHardwareVolumeButtons: Bool = true

    /// The switch means exactly one thing: *while Cue is your Lock Screen
    /// player, this device's volume controls the speaker.* So the player screen
    /// honours the same three conditions the Lock Screen path does — the switch,
    /// the Now Playing surface, and Super — instead of being a fourth thing the
    /// same switch separately turns on.
    ///
    /// It used to read the switch alone, which was survivable while that
    /// defaulted to off and lived in **Playback**. Once it defaulted to *on* and
    /// moved into a Super-gated section shown only under Now Playing, that split
    /// meaning became a trap: a non-subscriber, or anyone on Live Activity, got
    /// their volume buttons pointed at a Sonos group with the only switch for it
    /// greyed out or absent. Scoping the behaviour to where the switch is
    /// reachable is what closes that.
    private var enabled: Bool {
        // Now Playing is always the Lock Screen surface now (the setting that
        // chose it is gone), so the switch and Super are the conditions left.
        useHardwareVolumeButtons
            && featureGate.isAvailable(.hardwareVolumeButtons)
    }

    @State private var volumeView: MPVolumeView = {
        let v = MPVolumeView()
        v.alpha = 0.0001
        v.isUserInteractionEnabled = false
        return v
    }()

    /// Reading `owner` here is what registers observation on it, so the task
    /// re-runs when a longer-lived owner (a background session) takes the bridge
    /// or gives it back. The service refuses or ignores the calls as
    /// appropriate — this view doesn't need to know what else might hold it.
    /// Instance identity isn't part of the key: the service resolves its group
    /// by coordinator id at time of use, so a topology change replacing the
    /// `GroupRoom` instance doesn't orphan the bridge.
    private var claimKey: String? {
        guard enabled, let group else { return nil }
        return "\(group.coordinatorID)|\(HardwareVolumeService.shared.owner == .session)"
    }

    func body(content: Content) -> some View {
        content
            .background {
                if enabled, group != nil {
                    VolumeViewRepresentable(view: volumeView)
                        .frame(width: 1, height: 1)
                }
            }
            .task(id: claimKey) {
                if enabled, let group {
                    HardwareVolumeService.shared.start(
                        group: group,
                        sonosService: sonosService,
                        volumeView: volumeView
                    )
                } else {
                    HardwareVolumeService.shared.stop()
                }
            }
            .onDisappear {
                HardwareVolumeService.shared.stop()
            }
    }
}

extension View {
    /// The hardware volume buttons move `group` while this view is up. Nil
    /// gives them back to this device, so a view that follows the route can
    /// keep the one modifier whichever way it points.
    func hardwareVolumeControl(group: GroupRoom?) -> some View {
        modifier(HardwareVolumeControlModifier(group: group))
    }
}
#else
import SonosKit
import SwiftUI

extension View {
    func hardwareVolumeControl(group: GroupRoom?) -> some View { self }
}
#endif
