import SwiftUI
import SonosKit

@Observable
class Popover {
    var isShowing: Bool = false
    var text: String = ""
}

struct ContentView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popOver: Popover
    @Binding var selected: String?
    
    var body: some View {
        NavigationSplitView {
            List (sonosService.groups, selection: $selected) { group in
                NavigationLink(value: group) {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                                Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                            }
                            Text(group.coordinatorRoom.track.name)
                                .lineLimit(0)
                            Text(group.coordinatorRoom.track.artist)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                if group.coordinatorRoom.isPlaying {
                                    await sonosService.pause(ip: group.coordinatorRoom.ip)
                                } else {
                                    await sonosService.play(ip: group.coordinatorRoom.ip)
                                }
                            }
                        } label: {
                            Gauge(
                                value: group.coordinatorRoom.track.playbackPosition,
                                in: 0...group.coordinatorRoom.track.duration,
                                label: {

                                },
                                currentValueLabel: {
                                    Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                                        .foregroundStyle(.tint, .thickMaterial)
                                        .contentTransition(.symbolEffect(.automatic))
                                }
                            )
                            .tint(Color.primary.gradient)
                            .gaugeStyle(.accessoryCircularCapacity)
                            .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
                            .scaleEffect(0.6)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets())
                }
                .tag(group.coordinatorID)
            }
            .listStyle(.carousel)
        } detail: {
            if selected != nil, let group = sonosService.groups.first(where: { group in
                group.coordinatorID == selected!
            }) {
                TabView {
                    PlayerView(group: group)
                        .environment(sonosService)
                        .environment(popOver)
                    GroupVolumeControlScreen(group: group)
                }
            }
        }
        .onChange(of: selected) {
            guard let selected else { return }
            let selectedGroup = sonosService.groups.first(where: { room in
                room.coordinatorID == selected
            })

            guard let selectedGroup else { return }
            sonosService.selectedGroup = selectedGroup
        }
        .overlay {
            if popOver.isShowing {
                Rectangle()
                    .ignoresSafeArea()
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        Text(popOver.text)
                            .animation(nil)
                    }
                    .transition(.opacity)
            }
            if sonosService.groups.isEmpty {
                Rectangle()
                    .ignoresSafeArea()
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        Text("Searching...")
                            .animation(nil)
                    }
                    .transition(.opacity)
            }
        }
        .background(Color.clear)
    }
}

#Preview {
    ContentView(selected: .constant(nil))
        .environment(SonosService())
        .environment(Popover())
}

