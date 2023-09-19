import SwiftUI
import SonosKit
import VibesDS

struct DeviceListView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popOver: Popover
    @Binding var selected: String?

    var body: some View {
        @Bindable var sonosService = sonosService

        NavigationSplitView {
            List (selection: $selected) {
                SceneView()
                    .listRowBackground(Color.clear)
                ForEach($sonosService.sorted) { $group in
                    ZStack {
                        if group.tvMode {
                            TVCellView(group: $group)
                        } else {
                            ExtractedView(group: $group)
                        }
                    }
                    .tag(group.coordinatorID)
                }
            }
            .listStyle(.carousel)
        } detail: {
            if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                PlayerScreen(group: $sonosService.sorted[index])
            }
        }
        .safeAreaInset(edge: .bottom) {
            if sonosService.isSearching && sonosService.groups.isEmpty {
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
            if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                sonosService.selectedGroup = sonosService.sorted[index]
            } else {
                sonosService.selectedGroup = nil
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
        }
        .background(Color.clear)
        .onAppear {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
            sonosService.monitorWatch(useCache: true)
        }
//        .overlay {
//            VStack {
//                Text(!sonosService.sonosPulse.isCancelled ? "Running" : "Cancelled")
//                    .bold()
//                Spacer()
//            }
//            .ignoresSafeArea()
//        }
//        .overlay(alignment: .top) {
//            if sonosService.systemNotFound {
//                VStack {
//                    Text("Disconnected \(sonosService.isRunning ? "Running" : "Failed"), \(sonosService.lastKnownIP)")
//                        .bold()
//                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
//                    Button {
//                        sonosService.monitorWatch()
//                    } label: {
//                        Text("Search for System")
//                            .bold()
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .foregroundStyle(.thickMaterial)
//                    .padding()
//                }
//                .background {
//                    Rectangle()
//                        .foregroundStyle(.thinMaterial)
//                        .ignoresSafeArea()
//                }
//            }
//
//            if sonosService.groups.isEmpty {
//                VStack {
//                    Text("Empty \(sonosService.isRunning ? "Running" : "Failed")")
//                        .bold()
//                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
//                    Button {
//                        sonosService.monitorWatch()
//                    } label: {
//                        Text("Search for System")
//                            .bold()
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .foregroundStyle(.thickMaterial)
//                    .padding()
//                }
//                .background {
//                    Rectangle()
//                        .foregroundStyle(.thinMaterial)
//                        .ignoresSafeArea()
//                }
//            }
//        }
//        .animation(.smooth, value: sonosService.systemNotFound)
//        .animation(.smooth, value: sonosService.groups)
    }
}

#Preview {
    DeviceListView(selected: .constant(nil))
        .environment(SonosService())
        .environment(Popover())
}


struct ExtractedView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

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
