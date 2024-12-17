import SwiftUI
import SonosKit
import Combine
import SonosKit
import VibesDS

struct GroupMenuScreen: View {
    @State private var sonosService = SonosService.shared
    @State private var volumeTask: Task<Void, Error>?
    @State private var isLoading: Bool = false
    @State private var hoveredGroupId: String? // Add this property
    @State var showList: Bool = false

    var sizePassthrough: PassthroughSubject<CGSize, Never>?
    
    var body: some View {
        mainContent
            .overlay(
                GeometryReader { geometryProxy in
                    Color.clear
                        .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
                }
            )
            .onPreferenceChange(SizePreferenceKey.self) { size in
                sizePassthrough?.send(size)
            }
    }
    
    @ViewBuilder
    var mainContent: some View {
        @Bindable var sonosService = sonosService
        VStack(alignment: .leading) {
            ForEach(sortByNowPlaying) { $group in
                Section {
                    if group.coordinatorRoom.state == .active {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VibeContentArtworkView(content: group.coordinatorRoom.track.toPlayable)
                                    .frame(width: 48, height: 48)
                                Link(destination: URL(string: "clic://device?id=\(group.coordinatorRoom.id)")!) {
                                    VStack(alignment: .leading) {
                                        Text(group.coordinatorRoom.track.toPlayable.title)
                                        Text(group.coordinatorRoom.track.toPlayable.subtitle)
                                            .foregroundStyle(.secondary)
                                    }
                                    .lineLimit(1)
                                }
                                Spacer()
                                if group.coordinatorRoom.track != .empty {
                                    playPauseButton(for: group)
                                    nextTrackButton(for: group)
                                }
                            }
                            .foregroundStyle(.primary)
                            VolumeView(group: $group)
                                .frame(height: 16)
                        }
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .foregroundStyle(hoveredGroupId == group.coordinatorID ? Color(nsColor: .systemFill) : Color(nsColor: NSColor.secondarySystemFill))
                        }
                        .onHover { isHovered in
                            hoveredGroupId = isHovered ? group.coordinatorRoom.id : nil
                        }
                    }
                } header: {
                    HStack {
                        Text(group.nameWithCount)
                        if let battery = group.coordinatorRoom.battery {
                            Spacer()
                            Text((battery.percentage / 100), format: .percent)
                                .foregroundStyle(.secondary)
                            if battery.chargingState == .charging {
                                Image(systemName: "battery.100percent.bolt")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(battery.percentage > 90.0 ? Color.green.gradient : Color.orange.gradient)
                            }
                        }
                    }
                    .fontDesign(.rounded)
                    .foregroundStyle(.foreground)
                    .font(.title2)
                }
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .animation(.interactiveSpring, value: sortByNowPlaying.wrappedValue)
        .task {
            isLoading = true
            try? await sonosService.load(useCache: true)
            isLoading = false
        }
        .overlay {
            if isLoading, sonosService.sorted.isEmpty {
                ProgressView()
                    .padding(.vertical)
            }
        }
//        .safeAreaInset(edge: .top) {
//            Button("Click Me") { showList.toggle() }
//              .frame(width: 100, height: 20)
//              .overlay {
//                  if showList {
//                      List {
//                          Button("AA") {}
//                          Button("AA") {}
//                          Button("AA") {}
//                      }
//                      .frame(width: 200, height: 300)
//                      .offset(y: 160)
//                      .transition(.opacity)
//                      .padding()
//                      .clipShape(RoundedRectangle(cornerRadius: 12))
//                  }
//              }
//              .zIndex(1)
//              .animation(.spring, value: showList)
//        }
    }
    
    private func playPauseButton(for group: GroupRoom) -> some View {
        Button {
            Task {
                await sonosService.togglePlayback(ip: group.ip)
                group.coordinatorRoom.isPlaying.toggle()
            }
        } label: {
            playPauseLabel(for: group)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
    }
    
    private func playPauseLabel(for group: GroupRoom) -> some View {
        ZStack {
            if group.coordinatorRoom.track.duration > 0 {
                VibeGaugeView(
                    value: group.coordinatorRoom.track.playbackPosition,
                    total: group.coordinatorRoom.track.duration,
                    color: group.coordinatorRoom.isPlaying ? Color.primary : Color.primary.opacity(0.7),
                    lineWidth: 2
                )
                .frame(width: 30, height: 30)
            }
            Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                .font(.body)
                .contentTransition(.symbolEffect(.automatic))
        }
        .frame(width: 40, height: 40)
    }
    
    private func nextTrackButton(for group: GroupRoom) -> some View {
        Button {
            Task {
                await sonosService.next(ip: group.ip)
                try? await sonosService.updateGroups(from: [group])
            }
        } label: {
            Image(systemName: "forward.fill")
                .padding(4)
        }
        .buttonStyle(.plain)
        .disabled(!group.availableActions.contains(.next))
    }
    
    @MainActor
    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
        }
    }
    
    private var sortByNowPlaying: Binding<[GroupRoom]> {
        Binding(
            get: {
                sonosService.sorted.sorted(by: { $0.coordinatorRoom.isPlaying != $1.coordinatorRoom.isPlaying })
            },
            set: { newValue in
                sonosService.sorted = newValue
            }
        )
    }
}

#Preview {
    GroupMenuScreen(sizePassthrough: nil)
        .environment(SonosService.shared)
        .task {
            SonosService.shared.monitor()
        }
        .frame(height: 800)
}
