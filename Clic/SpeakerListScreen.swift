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
        .animation(.interactiveSpring, value: sonosService.sorted)
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
            if sonosService.sorted.isEmpty, sonosService.parserError == nil, !sonosService.systemState.notFound, !sonosService.isCellular {
                ProgressView()
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
        .onChange(of: router.selectedID) {
            if let id = router.selectedID, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                sonosService.selectedGroup = sonosService.sorted[index]
            }
        }
    }
    
}

fileprivate struct SpeakerGroupSection: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(Router.self) private var router
    @Environment(\.colorScheme) private var colorScheme

    var group: GroupRoom
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
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .scale).animation(.snappy(duration: 0))
                        ))
                        .opacity(group.TVMode ? 1 : 0)

                    HStack(alignment: .top) {
                        ArtworkView(group: group)
                            .frame(width: 72, height: 72)
                        ZoneView(group: group)
                        Spacer()
                        MediaControlsView(group: group)
                    }
                    .opacity(group.TVMode ? 0 : 1)
                    .id(group.coordinatorRoom.track.trackID)
                }
                .padding(.horizontal, 12)
                VolumeControlView(group: group, delayDrag: true)
            }
            .padding(.top, 12)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .dropDestinationPlay(on: group)
            .paywall(paywallEnabled)
            .overlay {
                Text(group.coordinatorRoom.state.reason)
                    .font(.title.smallCaps())
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.thickMaterial)
                    .paywall(paywallEnabled)
                    .opacity(group.isActive ? 0 : 1)
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
            .id(group.coordinatorRoom.track.trackID)
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
    var group: GroupRoom

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
                Text((battery.percentage / 100), format: .percent)
                    .foregroundStyle(.secondary)
                if battery.chargingState == .charging {
                    Image(systemName: "battery.100percent.bolt")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(battery.percentage > 90.0 ? Color.green.gradient : Color.orange.gradient)
                }
            }
        }
        .textCase(nil)
        .fontDesign(.rounded)
        .fontWeight(.semibold)
        .foregroundStyle(.foreground)
        .font(.headline)
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
