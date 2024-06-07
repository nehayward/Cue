import SwiftUI
import SonosKit
import MusicSearchKit

struct MenuInfoView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer

    @State private var coreFeatures = CoreFeatures()

    var group: GroupRoom
    @State private var playlists: [PlayableContent] = []

    var body: some View {
        Menu {
            Group {
                if let openInURL = group.coordinatorRoom.track.metadata?.openInURL {
                    if group.coordinatorRoom.track.musicService == .apple {
                        Link(destination: openInURL) {
                            Label("Open in Apple Music…", systemImage: "apple.logo")
                        }
                    }
                    if group.coordinatorRoom.track.musicService == .spotify {
                        Link(destination: openInURL) {
                            Label {
                                Text("Open in Spotify…")
                            } icon: {
                                MusicService.spotify.image
                            }
                        }
                    }

                    if group.coordinatorRoom.track.musicService == .tidal {
                        Link(destination: openInURL) {
                            Label {
                                Text("Open in Tidal…")
                            } icon: {
                                MediaSearchService.tidal.icon
                            }
                        }
                    }
                }
                if coreFeatures.nowPlaying, !group.TVMode {
                    Link(destination: group.coordinatorRoom.track.nowPlayingURL) {
                        Label("Open in NowPlaying…", image: .nowPlayingAppIcon)
                    }
                }
                if [.spotify, .apple, .library, .tidal].contains(group.coordinatorRoom.track.musicService) {
                    Button {
                        router.sheet(to: .mediaDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
                    } label: {
                        Label("View Album", systemImage: "smallcircle.circle.fill")
                    }

                    Button {
                        router.sheet(to: .artistDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
                    } label: {
                        Label("View Artist", systemImage: "music.mic")
                    }
                    //                let playable = group.coordinatorRoom.track.toPlayable
                    //                ShareLink(item: playable)
                    if !group.TVMode {
                        AddToPlaylistMenu(itemToAdd: group.coordinatorRoom.track.toPlayable)
                    }
                }
                Button {
                    router.sheet(to: .alarms(group: group))
                } label: {
                    Label("Alarms", systemImage: "alarm.fill")
                }

                SpeakerSettingsMenuView(group: group)

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
            }
        } label: {
            Image(systemName: "ellipsis")
                .padding(.vertical)
        }
    }
}
