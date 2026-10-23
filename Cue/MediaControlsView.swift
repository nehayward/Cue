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
            .accessibilityLabel("Group Speakers")
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
                // The running estimate, like the player's bar, so the two agree. A
                // ring this size moves under a pixel a second for most songs.
                PlaybackTimeline(
                    isRunning: group.coordinatorRoom.isClockRunning,
                    minimumInterval: 1,
                    position: { group.coordinatorRoom.estimatedPlaybackPosition() }
                ) { position in
                    PlaybackIconView(
                        value: position,
                        total: group.coordinatorRoom.track.duration,
                        isPlaying: group.coordinatorRoom.isPlaying,
                        isTransitioning: group.coordinatorRoom.isTransitioning
                    )
                }
                .font(.title)
            }
            .buttonStyle(.plain)
            .buttonBorderShape(.circle)
            .accessibilityLabel(group.coordinatorRoom.isPlaying ? "Pause" : "Play")
        }
        .tint(.primary)
    }
}

#Preview {
    MediaControlsView(group: .garage)
        .environment(SonosService())
        .environment(Router())
}
