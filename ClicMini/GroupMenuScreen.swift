import Combine
import CloudKit
import SonosKitMini
import SwiftUI
import Kingfisher

struct GroupMenuScreen: View {
    @State var showList: Bool = false
    @State private var sonosServiceMini = SonosMiniService.shared
    @State private var isLoading: Bool = false
    @State private var hoveredGroupId: String?
    
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
    
    var mainContent: some View {
        VStack(alignment: .leading) {
            ForEach($sonosServiceMini.sortedNowPlaying) { $group in
                Section {
                    if group.coordinatorRoom.state == .active {
                        VStack(alignment: .leading, spacing: 12) {
                            if group.tvSettings == nil {
                                HStack {
                                    Link(destination: URL(string: "clic://device?id=\(group.coordinatorRoom.id)")!) {
                                        KFImage.url(group.coordinatorRoom.track.sonosAlbumArtURL)
                                            .placeholder {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .foregroundStyle(.thinMaterial)
                                            }
                                            .loadDiskFileSynchronously()
                                            .diskCacheExpiration(.days(1))
                                            .fade(duration: 0.2)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 48, height: 48)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                        VStack(alignment: .leading) {
                                            Text(group.coordinatorRoom.track.song)
                                            Text(group.coordinatorRoom.track.artist)
                                                .foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1, reservesSpace: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    playPauseButton(for: group)
                                    nextTrackButton(for: group)
                                }
                                .foregroundStyle(.primary)
                                .transition(.opacity)
                            } else {
                                TVView(group: $group)
                                    .transition(.opacity)
                            }
                            VolumeMiniView(group: $group)
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
                        .transition(.opacity)
                    }
                } header: {
                    header(group)
                }
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .animation(.spring, value: sonosServiceMini.sortedNowPlaying)
        .onAppear {
            Task {
                isLoading = true
                try? await sonosServiceMini.load(useCache: true, keyPaths: [\.groupVolume, \.coordinatorRoom.track])
                isLoading = false
            }
        }
        .overlay {
            if isLoading, sonosServiceMini.sorted.isEmpty {
                ProgressView()
                    .padding(.vertical)
                    .controlSize(.small)
            } else if !isLoading, sonosServiceMini.sorted.isEmpty {
                Link(destination: URL(string: "clic://")!) {
                    Text("Sonos System not found, Launch Clic")
                        .padding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
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
    
    private func playPauseButton(for group: SonosGroup) -> some View {
        Button {
            Task {
                await sonosServiceMini.togglePlayback(ip: group.ip)
            }
        } label: {
            playPauseLabel(for: group)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .disabled(!group.availableActions.contains(.play))
    }
    
    private func playPauseLabel(for group: SonosGroup) -> some View {
        Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
            .font(.body)
            .contentTransition(.symbolEffect(.automatic))
            .frame(width: 40, height: 40)
    }
    
    private func nextTrackButton(for group: SonosGroup) -> some View {
        Button {
            Task {
                await sonosServiceMini.next(ip: group.ip)
                try? await sonosServiceMini.updateGroups(from: [group])
            }
        } label: {
            Image(systemName: "forward.fill")
                .padding(4)
        }
        .buttonStyle(.plain)
        .disabled(!group.availableActions.contains(.next))
    }
    
    @ViewBuilder
    fileprivate func header(_ group: SonosGroup) -> some View {
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

//#Preview {
//    GroupMenuScreen(sizePassthrough: nil)
//        .environment(SonosService.shared)
//        .task {
//            SonosService.shared.monitor()
//        }
//        .frame(height: 800)
//}
