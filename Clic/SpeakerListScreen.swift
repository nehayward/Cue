import CloudStorage
import SwiftUI
import SonosKit
import SubscriptionKit
import VibesDS
import RevenueCat
import RevenueCatUI

struct SpeakerListScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(AlertService.self) private var alertService
    @Environment(Router.self) private var router
    
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
    
    @State private var hoveredID: String? = nil
    
    var body: some View {
        @Bindable var sonosService = sonosService
        @Bindable var router = router
        
        List(sonosService.sorted, selection: $router.selectedID) { group in
            SpeakerGroupSection(group: group, hoveredID: $hoveredID)
        }
        .listSectionSpacing(10)
        .animation(.interactiveSpring, value: sonosService.sorted.map(\.topologyKey))
        .animation(.interactiveSpring, value: sonosService.sortOption)
        .environment(\.defaultMinListRowHeight, 40)
        .withAppRouter()
        .navigationBarTitle("", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.presentedSheet = .settings()
                } label: {
                    Image(systemName: "switch.2")
                }
                #if targetEnvironment(macCatalyst)
                .tint(.primary)
                #endif
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                #if targetEnvironment(macCatalyst)
                Menu {
                    ForEach(scenes) { scene in
                        SceneButton(scene: scene) {
                            if let content = scene.playableContent {
                                alertService.showAlertContent(with: content, subtitle: "Running \(scene.name)", symbolName: "bolt.fill")
                            } else {
                                alertService.showAlert(with: "Running \(scene.name)")
                            }
                            Task {
                                try? await sonosService.runScene(scene)
                            }
                        }
                    }
                } label: {
                    if !scenes.isEmpty {
                        Image(systemName: "bolt.fill")
                    } else {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Create Scene")
                                .font(.caption2)
                        }
                    }
                } primaryAction: {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    if subscriptionService.subscription.isActive {
                        if !scenes.isEmpty {
                            router.sheet(to: .scenes)
                        } else {
                            router.sheet(to: .createScene(content: nil))
                        }
                    } else {
                        router.sheet(to: .paywall)
                    }
                }
                .tint(.primary)
                #endif
                SortMenuView(sortOption: $sonosService.sortOption)
            }
        }
        .overlay(alignment: .center) {
            if sonosService.sorted.isEmpty,
               sonosService.parserError == nil,
               !sonosService.systemState.notFound,
               !sonosService.systemState.permissionDenied,
               !sonosService.isCellular {
                if sonosService.isRunning {
                    ProgressView()
                } else {
                    // No groups, no errors, and discovery isn't running — the
                    // user almost certainly bailed out of onboarding before
                    // granting Local Network. Offer a clear way back in
                    // instead of an indefinite spinner.
                    ContentUnavailableView {
                        Label("Set Up Clic", systemImage: "sparkles")
                    } description: {
                        Text("Finish the welcome flow to discover your Sonos speakers.")
                    } actions: {
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            router.presentedSheet = .onboard
                        } label: {
                            Text("Open Setup")
                        }
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    .background(.thinMaterial)
                }
            }

            if sonosService.isCellular {
                ContentUnavailableView {
                    Label("On Cellular", systemImage: "wifi.slash")
                } description: {
                    Text("Connect to WiFi to control your Sonos speakers.")
                }
                .background(.thinMaterial)
            } else if sonosService.systemState.notFound {
                ContentUnavailableView {
                    Label("Discover Devices", systemImage: "waveform.badge.magnifyingglass")
                } description: {
                    Text("Please ensure you're connected to WiFi and have a Sonos system setup.")
                } actions: {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        sonosService.monitor()
                    } label: {
                        Text("Search")
                    }
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .background(.thinMaterial)
            }
        }
        .overlay(alignment: .bottom) {
            VStack {
                if sonosService.systemState.permissionDenied {
                    Button {
                        // MARK: Settings Action
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Local Network Permission Needed", systemImage: "wifi.exclamationmark.circle.fill")
                            .bold()
                            .imageScale(.large)
                            .symbolEffect(.pulse.wholeSymbol)
                            .padding()
                            .background {
                                Capsule()
                                    .foregroundStyle(.ultraThinMaterial)
                            }
                    }
                    .transition(.scale)
                }
                
                if !subscriptionService.subscription.isActive {
                    PaywallButtonView()
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .transition(.scale)
                }
            }
        }
        .toolbar {
            #if !targetEnvironment(macCatalyst)
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    ForEach(scenes) { scene in
                        SceneButton(scene: scene) {
                            if let content = scene.playableContent {
                                alertService.showAlertContent(with: content, subtitle: "Running \(scene.name)", symbolName: "bolt.fill")
                            } else {
                                alertService.showAlert(with: "Running \(scene.name)")
                            }
                            Task {
                                try? await sonosService.runScene(scene)
                            }
                        }
                    }
                    Button {
                        router.sheet(to: .createScene(content: nil))
                    } label: {
                        Label("Create Scene", systemImage: "plus")
                    }
                } label: {
                    if !scenes.isEmpty {
                        Image(systemName: "bolt.fill")
                            .allowsHitTesting(false)
                    } else {
                        VStack {
                            Image(systemName: "bolt.fill")
                            Text("Create Scene")
                                .font(.caption2)
                        }
                        .allowsHitTesting(false)
                    }
                } primaryAction: {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    if subscriptionService.subscription.isActive {
                        if !scenes.isEmpty {
                            router.sheet(to: .scenes)
                        } else {
                            router.sheet(to: .createScene(content: nil))
                        }
                    } else {
                        router.sheet(to: .paywall)
                    }
                }
                .tint(.primary)
                Spacer()
                Button{
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router.sheet(to: .search())
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tint(.primary)
                Spacer()
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router.sheet(to: .browse())
                } label: {
                    Image("home.fill")
                }
                .tint(.primary)
            }
            #endif
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.spring, value: sonosService.isSearching)
        .animation(.spring, value: sonosService.systemState.notFound)
        .animation(.spring, value: sonosService.systemState.permissionDenied)
        .animation(.spring, value: sonosService.isCellular)
        .overlay(alignment: .top) {
            VStack {
                if sonosService.isCellular {
                    Label("Connect to Wi-Fi", systemImage: "wifi.slash")
                        .padding()
                        .background {
                            Capsule()
                                .foregroundStyle(.thickMaterial)
                        }
                        .frame(alignment: .top)
                        .fontDesign(.rounded)
                        .bold()
                        .transition(.asymmetric(insertion: .move(edge: .top), removal: .identity))
                }

                if sonosService.isSearching {
                    Label("Discovering Devices", systemImage: "waveform.badge.magnifyingglass")
                        .imageScale(.large)
                        .symbolEffect(.variableColor)
                        .padding()
                        .background {
                            Capsule()
                                .foregroundStyle(.ultraThinMaterial)
                        }
                        .transition(.push(from: .bottom).combined(with: .scale))
                        .offset(y: 50)
                }
            }
        }
    }
    
}

fileprivate struct SpeakerGroupSection: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(Router.self) private var router
    @Environment(\.colorScheme) private var colorScheme
    
    let group: GroupRoom
    @Binding var hoveredID: String?
    
    private var paywallEnabled: Bool {
        if subscriptionService.subscription.isActive { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
    }
    
    private var listRowBackground: Color {
        #if targetEnvironment(macCatalyst)
        Color(UIColor.secondarySystemBackground)
        #else
        colorScheme == .light ? Color.white : Color(uiColor: .secondarySystemFill)
        #endif
    }
    
    var body: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    TVModeViewCell(group: group)
                        .blur(radius: group.TVMode ? 0 : 10)
                        .opacity(group.TVMode ? 1 : 0)
                        .animation(.smooth, value: group.TVMode)
                    HStack(alignment: .top) {
                        ArtworkView(group: group)
                            .frame(width: 72, height: 72)
                        ZoneView(
                            radioStation: group.coordinatorRoom.radioStation ?? "",
                            song: group.coordinatorRoom.track.song,
                            artist: group.coordinatorRoom.track.artist
                        )
                        Spacer()
                        MediaControlsView(group: group)
                    }
                    .opacity(group.TVMode ? 0 : 1)
                }
                .padding(.horizontal, 12)
                VolumeControlView(group: group, delayDrag: true)
            }
            .padding(.top, 12)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .dropDestinationPlay(on: group)
            .paywall(paywallEnabled)
            .overlay {
                if !group.isActive {
                    InactiveSpeakerOverlay(room: group.coordinatorRoom)
                        .paywall(paywallEnabled)
                }
            }
            .disabled(!group.isActive)
            .listRowBackground(UIDevice.current.userInterfaceIdiom == .phone ? nil : background)
            .onHover { isHovered in
                if [.mac, .vision, .pad].contains(UIDevice.current.userInterfaceIdiom) {
                    withAnimation(.interactiveSpring) {
                        hoveredID = isHovered ? group.coordinatorID : nil
                    }
                }
            }
            .tag(group.coordinatorID)
            .foregroundStyle(.primary)
        } header: {
            SpeakerGroupHeader(group: group)
        }
        .geometryGroup()
        .headerProminence(.increased)
        .tint(.primary)
    }
    
    private var background: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                group.coordinatorID == router.selectedID ? Color(uiColor: .systemFill) :
                    hoveredID == group.coordinatorID ? Color(uiColor: .tertiarySystemFill) :
                    listRowBackground
            )
    }
}

fileprivate struct SpeakerGroupHeader: View {
    let group: GroupRoom
    
    var body: some View {
        HStack {
            Text(group.nameWithCount)
            if let sleepTimer = group.coordinatorRoom.sleepTimer, sleepTimer > Date() {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(Color.primary.gradient, .indigo)
                    Text(sleepTimer, style: .timer)
                        .monospacedDigit()
                }
            } else if let battery = group.coordinatorRoom.battery {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: batterySymbol(for: battery))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(batteryTint(for: battery))
                    Text((battery.percentage / 100), format: .percent)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .textCase(nil)
        .fontDesign(.rounded)
        .fontWeight(.semibold)
        .foregroundStyle(.foreground)
        .font(.headline)
    }

    /// Picks the battery SF symbol based on percentage + charging state.
    /// Charging always shows the bolt variant.
    private func batterySymbol(for battery: Battery) -> String {
        if battery.chargingState == .charging {
            return "battery.100percent.bolt"
        }
        switch battery.percentage {
        case 75...:    return "battery.100percent"
        case 50..<75:  return "battery.75percent"
        case 25..<50:  return "battery.50percent"
        case 10..<25:  return "battery.25percent"
        default:       return "battery.0percent"
        }
    }

    /// Tint logic: green when charging at the top, orange when charging
    /// from low, red when discharged < 15%, orange < 30%, otherwise neutral.
    private func batteryTint(for battery: Battery) -> Color {
        if battery.chargingState == .charging {
            return battery.percentage > 90 ? .green : .orange
        }
        switch battery.percentage {
        case 30...:    return .secondary
        case 15..<30:  return .orange
        default:       return .red
        }
    }
}

fileprivate struct SortMenuView: View {
    @Binding var sortOption: SonosSortOption
    
    var body: some View {
        Menu {
            ForEach(SonosSortOption.allCases) { option in
                Toggle(isOn: Binding(
                    get: { sortOption == option },
                    set: { isOn in
                        if isOn {
                            sortOption = option
                        }
                    }
                )) {
                    Label {
                        Text(option.title)
                    } icon: {
                        option.icon
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .accessibilityLabel(Text("Sort by"))
        }
        .tint(.primary)
    }
}

/// Overlay rendered on a speaker-list row when its coordinator is sleeping /
/// off / low battery. The row header already carries battery + name, so this
/// stays minimal: state icon + reason, with a relative "last seen" line.
private struct InactiveSpeakerOverlay: View {
    let room: Room

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: room.state.systemSymbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text(room.state.reason)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let lastSeen = room.lastSeen {
                Text(lastSeen.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

#Preview {
    SpeakerListScreen()
        .environment(SonosService.shared)
        .environment(SubscriptionService.shared)
        .environment(AlertService.shared)
        .environment(Router())
        .task {
            try? await SonosService.shared.updateGroups()
            try? await SonosService.shared.load(useCache: true)
        }
}
