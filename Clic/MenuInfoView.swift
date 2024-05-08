import SwiftUI
import SonosKit

struct MenuInfoView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    var group: GroupRoom

    var body: some View {
        Menu {
            if let openInURL = group.coordinatorRoom.track.metadata?.openInURL {
                if group.coordinatorRoom.track.musicService == .apple {
                    Link(destination: openInURL) {
                        Label("Open in Apple Music…", systemImage: "apple.logo")
                    }
                }
                if group.coordinatorRoom.track.musicService == .spotify {
                    Link(destination: openInURL) {
                        Label("Open in Spotify…", image: .spotifyLogo)
                    }
                }
            }
            Link(destination: group.coordinatorRoom.track.nowPlayingURL) {
                Label("Open in NowPlaying…", image: .nowPlayingAppIcon)
            }
            if [.spotify, .apple, .library].contains(group.coordinatorRoom.track.musicService) {
                Button {
                    router.sheet(to: .mediaDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
                } label: {
                    Label("View Album", systemImage: "rectangle.stack.fill")
                }

                Button {
                    router.sheet(to: .artistDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
                } label: {
                    Label("View Artist", systemImage: "music.mic.circle.fill")
                }
//                let playable = group.coordinatorRoom.track.toPlayable
//                ShareLink(item: playable)
            }
            ControlGroup {
                if let isCrossfaded = group.isCrossfaded {
                    Button {
                        Task {
                            await sonosService.setCrossfade(group: group, enabled: !isCrossfaded)
                        }
                    } label: {
                        Label("Crossfade is \(isCrossfaded ? "On" : "Off")", systemImage: isCrossfaded ? "waveform" : "waveform.slash")
                    }
                    .menuActionDismissBehavior(.disabled)
                }

                TimerMenuView(group: group)
            }
        } label: {
            Image(systemName: "ellipsis")
                .padding(.vertical)
        }
    }
}
