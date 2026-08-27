import SwiftUI
import SonosKit
import VibesDS

struct MediaControlsView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    
    let group: GroupRoom
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            GroupMenuButton(group: group) {
                router.presentedSheet = .groupScreen(group: group)
            } label: {
                GroupIconView()
            }
            .buttonStyle(.borderless)
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
                    value: group.coordinatorRoom.playbackPosition,
                    total: group.coordinatorRoom.track.duration,
                    isPlaying: group.coordinatorRoom.isPlaying,
                    isTransitioning: group.coordinatorRoom.isTransitioning
                )
                .font(.title)
            }
            .buttonStyle(.plain)
            .buttonBorderShape(.circle)
        }
        .tint(.primary)
    }
}

#Preview {
    MediaControlsView(group: .garage)
        .environment(SonosService())
        .environment(Router())
}
