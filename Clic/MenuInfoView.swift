import SwiftUI
import SonosKit
import MusicSearchKit

struct MenuInfoView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @State private var coreFeatures = CoreFeatures.shared

    var group: GroupRoom
    
    var body: some View {
        Menu {
            Group {
                OpenInServiceView(item:  group.coordinatorRoom.track.toPlayable)
                if coreFeatures.nowPlaying, !group.TVMode {
                    Link(destination: group.coordinatorRoom.track.nowPlayingURL) {
                        Label("Open in NowPlaying…", image: .nowPlayingAppIcon)
                    }
                }
                if [.spotify, .apple, .library, .tidal, .plex].contains(group.coordinatorRoom.track.musicService) {
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
                if [.spotify, .apple].contains(group.coordinatorRoom.track.musicService), group.coordinatorRoom.track.toPlayable.content.type != .libraryTrack {
                    Button {
                        QueueManager.shared.addToQueue(item: QueueItem(playableContent: group.coordinatorRoom.track.toPlayable.toRadio, group: group, position: .now, title: "Starting radio"))
                    } label: {
                        Label("Start Radio", systemImage: "radio.fill")
                    }
                }
                Button {
                    router.sheet(to: .alarms(group: group))
                } label: {
                    Label("Alarms", systemImage: "alarm.fill")
                }

                SpeakerSettingsMenuView(group: group)

                if !group.rooms.filter(\.isSoundbar).isEmpty {
                    if group.tvSettings == nil {
                        Button {
                            Task {
                                await sonosService.tvInput(group: group)
                            }
                        } label: {
                            Label("Switch to TV Input", systemImage: "tv")
                        }
                    }
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
            }
        } label: {
#if os(visionOS)
            Image(systemName: "ellipsis")
#else
            Image(systemName: "ellipsis")
                .padding(.vertical)
#endif
        }
#if os(visionOS)
        .tint(.clear)
#endif
    }
}
