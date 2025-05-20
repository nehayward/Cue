import Combine
import CloudKit
import SonosKitMini
import SwiftUI
import Kingfisher

struct GroupMenuScreen: View {
    @State private var showList: Bool = false
    @State private var isLoading: Bool = false
    @State private var hoveredSceneId: String?
    @State private var scenes: [SonosScene] = []
    
    @State private var sonosServiceMini = SonosMiniService.shared
    
    var sizePassthroughWindow: PassthroughSubject<CGSize, Never>?
    
    private var filteredDeviceBindings: [Binding<SonosDevice>] {
        return sonosServiceMini.sortedNowPlaying
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
            .fontDesign(.rounded)
            .onAppear {
                guard let data = NSUbiquitousKeyValueStore.default.data(forKey: "com.clic.scenes"),
                      let scenes = try? JSONDecoder().decode([SonosScene].self, from: data) else { return }
                
                self.scenes = scenes
            }
            .ignoresSafeArea()
            .padding(.vertical)
            .environment(sonosServiceMini)
    }
    
    var mainContent: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(filteredDeviceBindings) { $device in
                GroupItemView(device: $device)
                    .frame(maxHeight: 200)
            }
        }
        .padding(12)
        .frame(minWidth: 400, maxWidth: .infinity, alignment: .top)
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
        .overlay(alignment: .topTrailing) {
            HStack {
                Button {
                    showList.toggle()
                } label: {
                    Image(systemName: "bolt.fill")
                }
                .padding([.top, .trailing], 12)
                .overlay {
                    if showList {
                        ScrollView {
                            LazyVStack {
                                ForEach(scenes) { scene in
                                    SceneButtonView(scene: scene, showList: $showList)
                                }
                            }
                            .padding(.bottom, 60)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .foregroundStyle(.ultraThinMaterial)
                                .shadow(radius: 10)
                        )
                        .frame(width: 200, height: 400, alignment: .trailing)
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 0) {
                                Rectangle()
                                    .foregroundStyle(
                                        .linearGradient(
                                            colors: [.clear, .black.opacity(0.1), .black.opacity(0.3)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: 60)
                                    .allowsHitTesting(false)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .offset(x: -95, y: 220)
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
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
    @Binding var device: SonosDevice
    @State private var hovered : Bool = false
    
    var body: some View {
        let _ = Self._printChanges()

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
                                    MarqueeText(trackInfo.title)
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
                    .foregroundStyle(hovered ? Color(nsColor: .systemFill) : Color(nsColor: NSColor.secondarySystemFill))
            }
            .onHover { isHovered in
                hovered = isHovered
            }
        }
    }
    
    private func playPauseButton(for device: SonosDevice) -> some View {
        Button {
            Task {
                await SonosMiniService.shared.togglePlayback(ip: device.ip)
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
                await SonosMiniService.shared.next(ip: device.ip)
                try? await SonosMiniService.shared.updateDevices(from: [device])
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

struct SceneButtonView: View {
    var scene: SonosScene
    @Binding var showList: Bool
    @State private var sonosServiceMini = SonosMiniService.shared
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button {
            Task {
                withAnimation {
                    showList = false
                }
                try? await sonosServiceMini.runScene(scene)
            }
        } label: {
            Text(scene.name)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovering ?
                              Color(nsColor: .systemFill) :
                                Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            self.isHovering = isHovering
        }
    }
}
