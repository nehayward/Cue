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
                if group.tvMode {
                    TVModeView(group: group)
                } else {
                    ExtractedView(group: group)
                }
            }
            .listStyle(.carousel)
        } detail: {
            if let selected, let group = sonosService.groups.first(where: { group in
                group.coordinatorID == selected
            }) {
                PlayerScreen(group: group)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if sonosService.isSearching || sonosService.groups.isEmpty {
                Label("Searching", systemImage: "waveform.badge.magnifyingglass")
                    .imageScale(.large)
                    .symbolEffect(.variableColor)
                    .padding()
                    .background {
                        Capsule()
                            .foregroundStyle(.ultraThinMaterial)
                    }
                    .transition(.push(from: .bottom).combined(with: .scale))
            }
        }
        .animation(.spring, value: sonosService.isSearching)
        .onChange(of: selected) {
            guard let selected else {
                sonosService.selectedGroup = nil
                return
            }
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
        }
        .background(Color.clear)
        .onAppear {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                sonosService.monitorWatch()
            }
        }
    }
}

#Preview {
    ContentView(selected: .constant(nil))
        .environment(SonosService())
        .environment(Popover())
}


struct ExtractedView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Bindable var group: GroupRoom

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                    Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                }
                Text(group.coordinatorRoom.track.name)
                    .lineLimit(0)
                    .redacted(reason: group.coordinatorRoom.track.name.isEmpty ? .placeholder : [])
                
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
                .scaleEffect(0.6)
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .tag(group.coordinatorID)
        .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
    }
}
