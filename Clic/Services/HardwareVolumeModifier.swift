#if os(iOS) && !targetEnvironment(macCatalyst)
import Defaults
import MediaPlayer
import SonosKit
import SwiftUI

private struct VolumeViewRepresentable: UIViewRepresentable {
    let view: MPVolumeView
    func makeUIView(context: Context) -> MPVolumeView { view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct HardwareVolumeControlModifier: ViewModifier {
    let group: GroupRoom
    @Environment(SonosService.self) private var sonosService
    @AppStorage(AppStorageKeys.useHardwareVolumeButtons) private var enabled: Bool = false
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
    private var claimKey: String? {
        guard enabled else { return nil }
        return "\(group.coordinatorID)|\(HardwareVolumeService.shared.owner == .session)"
    }

    func body(content: Content) -> some View {
        content
            .background {
                if enabled {
                    VolumeViewRepresentable(view: volumeView)
                        .frame(width: 1, height: 1)
                }
            }
            .task(id: claimKey) {
                if enabled {
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
    func hardwareVolumeControl(group: GroupRoom) -> some View {
        modifier(HardwareVolumeControlModifier(group: group))
    }
}
#else
import SonosKit
import SwiftUI

extension View {
    func hardwareVolumeControl(group: GroupRoom) -> some View { self }
}
#endif
