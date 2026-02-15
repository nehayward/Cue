import Foundation
import Combine
import CloudKit
import SonosKitMini
import SwiftUI
import Kingfisher

struct GroupMenuScreen: View {
    @State private var sonosServiceMini = SonosMiniService.shared
    @State private var menuVisibilityService = MenuVisibilityService.shared
    @State private var isLoading: Bool = false
    @State private var hoveredSceneId: String?
    @State private var scenes: [SonosScene] = []
    @State private var isVisible = false
    @State private var show: Bool = false
    @State private var height: Double = 0
    
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
            .fontDesign(.rounded)
            .onAppear {
                guard let data = NSUbiquitousKeyValueStore.default.data(forKey: "com.clic.scenes"),
                      let scenes = try? JSONDecoder().decode([SonosScene].self, from: data) else { return }
                
                self.scenes = scenes
            }
            .padding(.vertical)
            .environment(sonosServiceMini)
            .task {
                try? await SonosMiniService.shared.loadWatch(useCache: true)
            }
            .onAppear {
                isVisible = true
                menuVisibilityService.setMenuVisible(true)
            }
            .onDisappear {
                isVisible = false
                menuVisibilityService.setMenuVisible(false)
            }
    }
    
    private var screenMaxHeight: Double {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.75
    }

    private var contentIdealHeight: Double {
        Double(filteredDeviceBindings.count) * 150
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
        .frame(minWidth: 400, minHeight: min(contentIdealHeight, screenMaxHeight))
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
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .padding(.vertical)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: isLoading)
        .animation(.snappy, value: sonosServiceMini.devices.map(\.isPlaying))
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
        }
        .safeArea(edge: .bottom) {
            HStack {
                SettingsMenuView()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal)
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

struct GroupHeader: View {
    let device: SonosDevice
    @State private var miniSettingsService = MiniSettingsService.shared
    
    var body: some View {
        HStack {
            Text(device.nameWithCount)
            
            Spacer()
            
            // Pin button
            Button {
                if miniSettingsService.isSpeakerPinned(id: device.id) {
                    miniSettingsService.unpinSpeaker()
                } else {
                    miniSettingsService.pinSpeaker(id: device.id)
                }
            } label: {
                Image(systemName: miniSettingsService.isSpeakerPinned(id: device.id) ? "pin.fill" : "pin")
                    .foregroundStyle(miniSettingsService.isSpeakerPinned(id: device.id) ? AnyShapeStyle(.accent.gradient) : AnyShapeStyle(.secondary))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(miniSettingsService.isSpeakerPinned(id: device.id) ? "Unpin from menu bar" : "Pin to menu bar")
            
            if let battery = device.battery {
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
