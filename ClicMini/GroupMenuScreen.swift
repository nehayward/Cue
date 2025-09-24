import Combine
import CloudKit
import SonosKitMini
import SwiftUI
import Kingfisher

struct GroupMenuScreen: View {
    @State private var sonosServiceMini = SonosMiniService.shared
    @State private var isLoading: Bool = false
    @State private var hoveredSceneId: String?
    @State private var scenes: [SonosScene] = []
    @State private var isVisible = false
    @State private var show: Bool = false
    
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
            .task {
                try? await SonosMiniService.shared.loadWatch(useCache: true)
            }
            .onAppear {
                isVisible = true
            }
            .onDisappear {
                isVisible = false
            }
    }
    
    var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(filteredDeviceBindings) { $device in
                    GroupItemView(isVisible: $isVisible, device: $device)
                        .frame(maxHeight: 200)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 400, minHeight: 800)
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
        .animation(.snappy, value: isLoading)
        .animation(.snappy, value: sonosServiceMini.devices)
//        .overlay(alignment: .topTrailing) {
//            HStack {
//                Button {
//                    showList.toggle()
//                } label: {
//                    Image(systemName: "bolt.fill")
//                }
//                .padding([.top, .trailing], 12)
//                .overlay {
//                    if showList {
//                        ScrollView {
//                            LazyVStack {
//                                ForEach(scenes) { scene in
//                                    SceneButtonView(scene: scene, showList: $showList)
//                                }
//                            }
//                            .padding(.bottom, 60)
//                        }
//                        .background(
//                            RoundedRectangle(cornerRadius: 12)
//                                .foregroundStyle(.ultraThinMaterial)
//                                .shadow(radius: 10)
//                        )
//                        .frame(width: 200, height: 400, alignment: .trailing)
//                        .overlay(alignment: .bottom) {
//                            VStack(spacing: 0) {
//                                Rectangle()
//                                    .foregroundStyle(
//                                        .linearGradient(
//                                            colors: [.clear, .black.opacity(0.1), .black.opacity(0.3)],
//                                            startPoint: .top,
//                                            endPoint: .bottom
//                                        )
//                                    )
//                                    .frame(height: 60)
//                                    .allowsHitTesting(false)
//                            }
//                        }
//                        .clipShape(RoundedRectangle(cornerRadius: 12))
//                        .offset(x: -95, y: 220)
//                        .padding()
//                    }
//                }
//            }
//            .frame(maxWidth: .infinity, alignment: .trailing)
        .safeArea(edge: .top) {
//            if #available(macOS 26.0, *) {
                HStack {
//                    Button {
//                        show.toggle()
//                    } label: {
//                        Text("Group")
//                    }
//                    .popover(isPresented: $show) {
//                        Text("HER?")
//                    }
                    Menu {
                        ForEach(scenes) { scene in
                            SceneButtonView(scene: scene)
                        }
                    } label: {
                        Image(systemName: "bolt.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
//                .buttonStyle(.glassProminent)
//                .buttonBorderShape(.circle)
//            }
        }
        .safeArea(edge: .bottom) {
            if #available(macOS 26.0, *) {
                HStack {
                   SettingsMenuView()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)

            }
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
    @Binding var isVisible: Bool
    @Binding var device: SonosDevice
    @State private var hovered: Bool = false
    
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
                            KFImage.url(device.track.sonosAlbumArtURL)
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
                            
//                            if let trackInfo = device.currentTrackMetadata {
//                                VStack(alignment: .leading) {
//                                    MarqueeText(trackInfo.title)
//                                    Text(trackInfo.creator)
//                                        .foregroundStyle(.secondary)
//                                }
//                                .lineLimit(1, reservesSpace: true)
//                                .frame(maxWidth: .infinity, alignment: .leading)
//                            }
                            
                            VStack(alignment: .leading) {
                                if isVisible {
                                    MarqueeText(device.track.song)
                                } else {
                                    Text(device.track.song)
                                }
                                Text(device.track.artist)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1, reservesSpace: true)
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
                    TVView(device: device)
                        .transition(.scale.combined(with: .opacity))
                }
                
                VolumeControlView(device: $device)
                    .frame(height: 16)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(hovered ? Color(nsColor: .systemFill) : Color(nsColor: NSColor.secondarySystemFill))
            }
            .geometryGroup()
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
            PlaybackIconView(value: Double(device.track.elapsed.components.seconds), total: Double(device.track.duration.components.seconds), isPlaying: device.isPlaying)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
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
                try? await SonosMiniService.shared.updateWatchDevices(from: [device])
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
    
    @State private var sonosServiceMini = SonosMiniService.shared
    
    var body: some View {
        Button {
            Task {
                try? await sonosServiceMini.runScene(scene)
            }
        } label: {
            Text(scene.name)
            if let url = scene.playableContent?.thumbnail, !url.absoluteString.isEmpty {
                KFImage.url(url)
                    .setProcessors([
                        RoundCornerImageProcessor(cornerRadius: .infinity),
                        ResizingImageProcessor(referenceSize: CGSize(width: 24, height: 24), mode: .aspectFit)
                    ])
                    .cancelOnDisappear(true)
                    .resizable() // Needed to allow resizing in SwiftUI
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(.circle)
            }
            
        }
    }
}

extension View {
    @ViewBuilder
    func safeArea<V>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> some View where V : View {
        if #available(iOS 26.0, macOS 26, *) {
            self
                .safeAreaBar(edge: edge, content: content)
        } else {
            self
                .safeAreaInset(edge: edge, content: content)
        }
    }
}

struct PreferencesCogButton: View {
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isHovered ? .accentColor : .secondary)
                .padding(8)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Preferences")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
