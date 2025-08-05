import CloudStorage
import SwiftUI
import SonosKit
import SubscriptionKit
import VibesDS
import RevenueCat
import RevenueCatUI

struct DeviceListMainView: View {
    @Environment(SonosService.self) var sonosService
    @Environment(SubscriptionService.self) var subscriptionService
    @Environment(AlertService.self) var alertService
    @Environment(Router.self) var router

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var alertService = alertService
        @Bindable var sonosService = sonosService
        @Bindable var router = router

//        // MARK: Add Back for Debugging
//        let _ = Self._printChanges()

        NavigationStack(path: $router.path) {
            List (sonosService.sorted) { group in
                Section {
                    if group.coordinatorRoom.state == .active {
                        Button {
                            HapticManager.shared.fireHaptic(.selection)
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        } label: {
                            VStack(spacing: 12) {
                                ZStack {
                                    TVModeViewCell(group: group)
                                        .transition(.asymmetric(
                                            insertion: .opacity,
                                            removal: .opacity.combined(with: .scale).animation(.snappy(duration: 0))
                                        ))
                                        .padding(.horizontal, 12)
                                        .opacity(group.TVMode ? 1 : 0)
                                    
                                    HStack(alignment: .top) {
                                        ArtworkView(group: group)
                                            .frame(width: 72, height: 72)
                                        ZoneView(group: group)
                                        Spacer()
                                        MediaControlsView(group: group)
                                    }
                                    .padding(.horizontal, 12)
                                    .opacity(group.TVMode ? 0 : 1)
                                }
                                VolumeControlView(group: group, delayDrag: true)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                        .dropDestinationPlay(on: group)
                        .paywall(enabled(group: group))
                    } else {
                        Text(group.coordinatorRoom.state.reason)
                            .padding(.vertical, 8)
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                            .paywall(enabled(group: group))
                            .listRowBackground(Color(UIColor.secondarySystemBackground))
                            .frame(maxWidth: .infinity, alignment: .center)
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
                    .headerProminence(.increased)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .animation(.interactiveSpring, value: sonosService.sorted)
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SortMenu(sortOption: $sonosService.sortOption)
                }
            }
            .overlay(alignment: .center) {
                if sonosService.sorted.isEmpty, sonosService.parserError == nil, !sonosService.systemState.notFound {
                    ProgressView()
                }

                if sonosService.systemState.notFound {
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
                        //                           .bold()
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
                    } label: {
                        if !scenes.isEmpty {
                            Image(systemName: "bolt.fill")
                        } else {
                            VStack {
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
                    Spacer()
                    Button{
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.sheet(to: .search())
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .tint(.primary)
                    Spacer()
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.sheet(to: .browse())
                    } label: {
                        Image(systemName: "music.note.house.fill")
                    }
                    .tint(.primary)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .withAlert()
        .animation(.spring, value: sonosService.sorted)
        .animation(.spring, value: sonosService.isSearching)
        .animation(.bouncy, value: sonosService.networkMonitorService.isConnected)
        .animation(.spring, value: sonosService.systemState.notFound)
        .animation(.spring, value: sonosService.systemState.permissionDenied)
        .animation(.spring, value: alertService.alert.isShowing)
        .overlay(alignment: .top) {
            VStack {
                if !sonosService.networkMonitorService.isConnected {
                    Label("Can't find System, Connect to Wi-Fi", systemImage: "wifi.slash")
                        .padding()
                        .background {
                            Capsule()
                                .foregroundStyle(.thickMaterial)
                        }
                        .frame(alignment: .top)
                        .fontDesign(.rounded)
                        .bold()
                        .transition(.asymmetric(insertion: .move(edge: .top), removal: .identity))
                        .offset(y: sonosService.networkMonitorService.isConnected ? 0 : -300)
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

    private func enabled(group: GroupRoom) -> Bool {
        if subscriptionService.subscription.isActive { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
    }
}

struct SortMenu: View {
    @Binding var sortOption: SonosSortOption
    
    var body: some View {
        Menu {
            Picker("Sort by", selection: $sortOption) {
                ForEach(SonosSortOption.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .accessibilityLabel(Text("Sort by"))
        }
        .tint(.primary)
    }
}

#Preview {
    DeviceListMainView()
        .environment(SonosService.shared)
        .environment(SubscriptionService.shared)
        .environment(AlertService.shared)
        .environment(Router())
        .task {
            try? await SonosService.shared.updateGroups()
            try? await SonosService.shared.load(useCache: true)
        }
}
