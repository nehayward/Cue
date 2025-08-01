import SwiftUI
import SonosKit
import MusicSearchKit

struct MenuInfoView: View {
    @Environment(Router.self) var router: Router
    @Environment(\.liveActivityManager) var liveActivityManager
    @State private var coreFeatures = CoreFeatures.shared

    var group: GroupRoom
    
    var body: some View {
        Menu {
            VStack {
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
                
                if group.playbackService != .lineIn, group.coordinatorRoom.supportsLineIn {
                    Button {
                        Task {
                            await SonosService.shared.switchToLineIn(group: group)
                            await SonosService.shared.play(ip: group.ip)
                        }
                    } label: {
                        Label("Switch to Line In", systemImage: "audio.jack.stereo")
                    }
                }
                
                if !group.rooms.filter(\.isSoundbar).isEmpty {
                    if group.tvSettings == nil {
                        Button {
                            Task {
                                await SonosService.shared.tvInput(group: group)
                            }
                        } label: {
                            Label("Switch to TV Input", systemImage: "tv")
                        }
                    }
                }
                
                if group.playbackService != .queue {
                    Button {
                        Task {
                            await SonosService.shared.switchToQueueInput(group: group)
                        }
                    } label: {
                        Label("Switch to Queue", systemImage: "music.note.list")
                    }
                }
                
                #if os(iOS) && !targetEnvironment(macCatalyst)
                LiveActivityMenu(group: group)
                #endif
                SpeakerSettingsMenuView(group: group)
                
                ControlGroup {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        Task {
                            await SonosService.shared.setGroupMute(group: group, mute: !group.isMuted)
                        }
                    } label: {
                        Label {
                            Text("\(group.isMuted ? "Unmute" : "Mute")")
                        } icon: {
                            Image(group.isMuted ? "speaker.wave.3.slash.fill" : "speaker.wave.3.fill", variableValue: group.groupVolume/100)
                                .resizable()
                                .scaledToFit()
                                .symbolRenderingMode(group.isMuted ? .hierarchical : .monochrome)
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(.primary)
                                .frame(width: UIDevice.current.userInterfaceIdiom == .phone ? 18 : 24, height: UIDevice.current.userInterfaceIdiom == .phone ? 18 : 24, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)

                    if let isCrossfaded = group.isCrossfaded {
                        Button {
                            Task {
                                await SonosService.shared.setCrossfade(group: group, enabled: !isCrossfaded)
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
            
#elseif targetEnvironment(macCatalyst)
            Label("Menu", systemImage: "ellipsis")
                .padding(.vertical)
#else
            Image(systemName: "ellipsis")
                .padding(.vertical)
#endif
        }
        .id(group.coordinatorID)
        .accessibilityLabel("Menu")
        .help("Menu")
#if os(visionOS)
        .tint(.clear)
#endif
    }
}

struct LiveActivityMenu: View {
    @Environment(\.liveActivityManager) var liveActivityManager
    var group: GroupRoom

    var body: some View {
        Button {
            Task {
                if liveActivityManager.isActivityDisabled(id: group.coordinatorID) {
                    liveActivityManager.enableActivity(id: group.coordinatorID)
                } else {
                    liveActivityManager.disableActivity(id: group.coordinatorID)
                }
            }
        } label: {
            Text(liveActivityManager.isActivityDisabled(id: group.coordinatorID) ? "Enable Live Activity for \(group.coordinatorRoom.name)" : "Disable Live Activity for \(group.coordinatorRoom.name)")
            Text("Show playback controls on lock screen")
                .foregroundStyle(.secondary)
            Image(systemName: "inset.filled.capsule")
        }
    }
}
