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
    
    var sizePassthroughWindow: PassthroughSubject<CGSize, Never>?
    
    private var filteredDeviceBindings: [Binding<SonosDevice>] {
        sonosServiceMini.sortedNowPlaying
            .enumerated()
            .filter { !$0.element.isHidden }
            .filter { $0.element.state == .active }
            .map { index, _ in
                $sonosServiceMini.sortedNowPlaying[index]
            }
    }
    
    var body: some View {
        mainContent
            .overlay(
                GeometryReader { geometryProxy in
                    Color.clear
                        .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
                        .onAppear {
                            sizePassthroughWindow?.send(geometryProxy.size)
                        }
                }
            )
            .onPreferenceChange(SizePreferenceKey.self) { size in
                sizePassthroughWindow?.send(size)
            }
            .frame(height: CGFloat(filteredDeviceBindings.count * 120 + (filteredDeviceBindings.isEmpty ? 44 : 0)))
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: filteredDeviceBindings.count)
            .fontDesign(.rounded)
    }
    
    var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(filteredDeviceBindings) { $device in
                GroupItemView(device: $device, hoveredGroupId: $hoveredGroupId)
                    .frame(maxHeight: 200)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9)
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.4)
                            .combined(with: .opacity)
                    ))
                    .id(device.id)
            }
        }
        .padding(12)
        .frame(minWidth: 400, maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: filteredDeviceBindings.map { $0.wrappedValue.id })
        .onAppear {
            Task {
                isLoading = true
                try? await sonosServiceMini.load(useCache: true)
                isLoading = false
            }
        }
        .overlay {
            if isLoading, filteredDeviceBindings.isEmpty {
                ProgressView()
                    .padding(.vertical)
                    .controlSize(.small)
                    .transition(.opacity)
            } else if !isLoading, filteredDeviceBindings.isEmpty {
                Link(destination: URL(string: "clic://")!) {
                    Text("Sonos System not found, Launch Clic")
                        .padding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: isLoading)
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
    
    @ViewBuilder
    fileprivate func header(_ device: SonosDevice) -> some View {
        HStack {
            Text(device.nameWithCount)
            if let battery = device.battery {
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
        .animation(.spring(response: 0.3), value: device.nameWithCount)
        .animation(.spring(response: 0.3), value: device.battery)
    }
}

struct GroupItemView: View {
    @State private var sonosServiceMini = SonosMiniService.shared
    @Binding var device: SonosDevice
    @Binding var hoveredGroupId: String?
    
    var body: some View {
        Section {
            deviceContent
        } header: {
            GroupHeader(device: device)
        }
    }
    
    private var deviceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                if !device.isTVMode {
                    HStack(spacing: 0) {
                        Link(destination: URL(string: "clic://device?id=\(device.id)")!) {
                            KFImage.url(device.sonosAlbumARTURL)
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
                                .overlay(alignment: .bottomTrailing) {
                                    device.musicServiceType.icon
                                        .frame(width: 12, height: 12)
                                }
                                .overlay {
                                    if device.groupIsMuted {
                                        Image(systemName: "speaker.slash.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundStyle(.primary)
                                            .frame(width: 24, height: 24)
                                            .bold()
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                            .background {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .foregroundStyle(.ultraThinMaterial)
                                            }
                                            .clipped()
                                            .transition(.opacity)
                                    }
                                }
                                .animation(.spring, value: device.groupIsMuted)
#if DEBUG && SCREENSHOT
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.ultraThinMaterial)
                                }
#endif
                            
                            if let trackInfo = device.currentTrackMetadata {
                                VStack(alignment: .leading) {
                                    Text(trackInfo.title)
                                    Text(trackInfo.creator)
                                        .foregroundStyle(.secondary)
                                }
                                .lineLimit(1, reservesSpace: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            //                                        VStack(alignment: .leading) {
                            //                                            Text(device.track.song)
                            //                                            Text(device.track.artist)
                            //                                                .foregroundStyle(.secondary)
                            //                                        }
                            //                                        .lineLimit(1, reservesSpace: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            playPauseButton(for: device)
                            nextTrackButton(for: device)
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: device.isPlaying)
                    }
                    .foregroundStyle(.primary)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                } else {
                    TVView(device: $device)
                        .transition(.scale.combined(with: .opacity))
                }
                
                VolumeMiniView(device: $device)
                    .frame(height: 16)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(hoveredGroupId == device.id ? Color(nsColor: .systemFill) : Color(nsColor: NSColor.secondarySystemFill))
            }
            .onHover { isHovered in
                hoveredGroupId = isHovered ? device.id : nil
            }
        }
    }
    
    private func playPauseButton(for device: SonosDevice) -> some View {
        Button {
            Task {
                await sonosServiceMini.togglePlayback(ip: device.ip)
            }
        } label: {
            playPauseLabel(for: device)
                .frame(minWidth: 44, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .disabled(!device.availableActions.contains(.play))
    }
    
    private func playPauseLabel(for device: SonosDevice) -> some View {
        Image(systemName: device.isPlaying ? "pause.fill" : "play.fill")
            .font(.body)
            .contentTransition(.symbolEffect(.automatic))
    }
    
    private func nextTrackButton(for device: SonosDevice) -> some View {
        Button {
            Task {
                await sonosServiceMini.next(ip: device.ip)
                try? await sonosServiceMini.updateDevices(from: [device])
            }
        } label: {
            Image(systemName: "forward.fill")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!device.availableActions.contains(.next))
    }
}

struct GroupHeader: View {
    let device: SonosDevice
    
    var body: some View {
        HStack {
            Text(device.nameWithCount)
            if let battery = device.battery {
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
