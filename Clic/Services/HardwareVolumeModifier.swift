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

    /// The Now Playing session runs the same bridge app-wide (and from its own
    /// window-parked volume view) whenever it's active. Reading `isActive` here
    /// registers observation, so this task re-runs and hands the bridge back
    /// when the session ends.
    private var sessionOwnsBridge: Bool {
        NowPlayingSessionService.shared.isActive
    }

    func body(content: Content) -> some View {
        content
            .background {
                if enabled, !sessionOwnsBridge {
                    VolumeViewRepresentable(view: volumeView)
                        .frame(width: 1, height: 1)
                }
            }
            .task(id: enabled && !sessionOwnsBridge ? group.coordinatorID : nil) {
                if enabled, !sessionOwnsBridge {
                    HardwareVolumeService.shared.start(
                        group: group,
                        sonosService: sonosService,
                        volumeView: volumeView
                    )
                } else if !sessionOwnsBridge {
                    HardwareVolumeService.shared.stop()
                }
            }
            .onDisappear {
                guard !sessionOwnsBridge else { return }
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
