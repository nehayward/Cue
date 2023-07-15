import SwiftUI
import SonosKit

@Observable
class Popover {
    var isShowing: Bool = false
    var text: String = ""
}

struct ContentView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var selected: String? = nil

    @Environment(Popover.self) var popOver: Popover

    var body: some View {
        NavigationSplitView {
            List (sonosService.groups, selection: $selected) { group in
                NavigationLink(value: group) {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: "hifispeaker")
                                Text(group.coordinatorRoom.name)
                            }
                            Text(group.coordinatorRoom.track.name)
                                .lineLimit(0)
                            Text(group.coordinatorRoom.track.artist)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            Task {
                                if group.coordinatorRoom.isPlaying {
                                    await sonosService.pause(ip: group.coordinatorRoom.ip)
                                } else {
                                    await sonosService.play(ip: group.coordinatorRoom.ip)
                                }
                            }
                        }, label: {
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
                        })
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets())
                }
                .tag(group.coordinatorID)
            }
            .listStyle(.carousel)
        } detail: {
            if selected != nil {
                PlayerView(group: sonosService.groups.first(where: { group in
                    group.coordinatorID == selected!
                })!)
                .environment(sonosService)
                .environment(popOver)
            }
        }
        .task {
            await sonosService.load()
        }
        .onAppear {
            Task {
                try await Task.sleep(for: .seconds(1))
                selected = sonosService.groups.first(where: { room in
                    room.coordinatorRoom.isPlaying
                })?.coordinatorID
                print(selected)
            }
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
    ContentView()
        .environment(SonosService())
        .environment(Popover())
}

