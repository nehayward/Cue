import SwiftUI
import SonosKit
import VibesDS

struct MediaControlsView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    
    @Binding var group: GroupRoom
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Button {
                router.presentedSheet = .groupScreen(group: group)
            } label: {
                GroupIconView()
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            Button {
                Task {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    if group.coordinatorRoom.isPlaying {
                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                }
            } label: {
                PlaybackIconView(
                    value: group.coordinatorRoom.track.playbackPosition,
                    total: group.coordinatorRoom.track.duration,
                    isPlaying: group.coordinatorRoom.isPlaying
                )
            }
            .buttonStyle(.plain)
            .buttonBorderShape(.circle)
        }
    }
}

#Preview {
    MediaControlsView(group: .constant(.garage))
        .environment(SonosService())
        .environment(Router())
}
