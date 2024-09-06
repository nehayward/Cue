import NukeUI
import Collections
import SwiftUI
import MusicSearchKit
import SonosKit

struct PlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popOver: Popover
    
    @Binding var group: GroupRoom
    @State private var isIdle: Bool = true
    @State private var showGroup: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    
    var body: some View {
        VStack(spacing: 4) {
            ThumbnailView(content: group.coordinatorRoom.track.toPlayable)
                .focusable()
                .digitalCrownRotation(detent: $group.groupVolume,
                                      from: 0,
                                      through: 100,
                                      by: 2,
                                      sensitivity: .low,
                                      isContinuous: false,
                                      isHapticFeedbackEnabled: true,
                                      onChange: { crownEvent in
                    isIdle = false
                    popOver.isShowing = !isIdle
                    popOver.text = String(format: "%.0f", group.groupVolume)
                }, onIdle: {
                    isIdle = true
                    withAnimation {
                        popOver.isShowing = !isIdle
                    }
                })
            Text(group.coordinatorRoom.track.song)
                .bold()
                .lineLimit(1)
            Text(group.coordinatorRoom.track.artist)
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    Task {
                        await sonosService.previous(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Image(systemName: "backward.fill")
                }
                .controlSize(.mini)
                .clipShape(Circle())
                Button(action: {
                    Task {
                        if group.coordinatorRoom.isPlaying {
                            WKInterfaceDevice.current().play(.stop)
                            await sonosService.pause(ip: group.coordinatorRoom.ip)
                        } else {
                            WKInterfaceDevice.current().play(.start)
                            await sonosService.play(ip: group.coordinatorRoom.ip)
                        }
                    }
                }, label: {
                    ZStack {
                        Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                            .renderingMode(.template)
                            .foregroundColor(.primary)
                            .contentTransition(.symbolEffect(.automatic))
                        Gauge(
                            value: group.coordinatorRoom.track.playbackPosition,
                            in: 0...group.coordinatorRoom.track.duration,
                            label: {
                                
                            },
                            currentValueLabel: {
                                EmptyView()
                            }
                        )
                        .tint(group.coordinatorRoom.isPlaying ? .accentColor : Color.secondary)
                        .gaugeStyle(.accessoryCircularCapacity)
                        .animation(.spring, value: group.coordinatorRoom.track.playbackPosition)
                        .frame(width: 24, height: 24)
                    }
                })
                .clipShape(Circle())
                .frame(width: 48, height: 48)
                Button {
                    WKInterfaceDevice.current().play(.click)
                    Task {
                        await sonosService.next(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Image(systemName: "forward.fill")
                }
                .controlSize(.mini)
                .clipShape(Circle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGroup.toggle()
                } label: {
                    Image(systemName: "hifispeaker.fill")
                        .fontDesign(.rounded)
                        .foregroundStyle(.foreground)
                }
            }
        }
        .sheet(isPresented: $showGroup) {
            GroupScreen(coordinatorID: group.coordinatorID)
        }
        .onChange(of: group.groupVolume) {
            if isIdle { return }
            volumeTask?.cancel()
            volumeTask = Task {
                await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(group.groupVolume))
            }
        }
        .onChange(of: sonosService.selectedGroup) {
            if group != sonosService.selectedGroup, let selectedGroup = sonosService.selectedGroup {
                group = selectedGroup
            }
        }
//        .onChange(of: group) {
//            print("Refreshed", group)
//            sonosService.selectedGroup = group
//            // MARK: Refresh
//            Task {
//                guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else { return }
//                let previousArtwork = group.coordinatorRoom.track.artworkURL
//                group.coordinatorRoom.track = track
//                if previousArtwork != nil {
//                    group.coordinatorRoom.track.artworkURL = previousArtwork
//                }
//                guard let artworkURL = await sonosService.getArtwork(from: track, size: 100) else {
//                    return
//                }
//                if artworkURL != previousArtwork {
//                    group.coordinatorRoom.track.artworkURL = artworkURL
//                }
//            }
//        }
        .navigationTitle(group.nameWithCount)
        .animation(.spring, value: popOver.isShowing)
        .animation(.spring, value: group.coordinatorRoom.track.artworkURL)
        .task {
            self.group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
        }
    }
}

#Preview {
    NavigationStack {
        PlayerView(group: .constant(.garage))
            .environment(SonosService())
            .environment(Popover())
        
    }
}
