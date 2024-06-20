import CloudStorage
import SwiftUI
import SonosKit
import SubscriptionKit
import VibesDS
import RevenueCat
import RevenueCatUI

struct DeviceListMainView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(AlertService.self) var alertService: AlertService
    @Environment(Router.self) var router: Router

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var alertService = alertService
        @Bindable var sonosService = sonosService
        @Bindable var router = router

        // MARK: Add Back for Debugging
//        let _ = Self._printChanges()

        NavigationStack(path: $router.path) {
            List ($sonosService.sorted) { $group in
                Section {
                    if group.coordinatorRoom.state == .active {
                        Button {
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        } label: {
                            VStack(spacing: 12) {
                                if group.tvSettings != nil {
                                    TVModeViewCell(group: $group)
                                } else {
                                    HStack(alignment: .top) {
                                        ArtworkView(group: $group)
                                            .frame(width: 72, height: 72)
                                        ZoneView(group: $group)
                                        Spacer()
                                        MediaControlsView(group: $group)
                                    }
                                }
                                VolumeControlView(group: $group, touchDelay: 0.05)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: group.TVMode ? 12 : 10, trailing: 12))
                        .dropDestinationPlay(on: group)
                    } else {
                        Text(group.coordinatorRoom.state.reason)
                            .padding(.vertical, 8)
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
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
                .redacted(reason: enabled(group: group) ? [] : .placeholder)
                .disabled(!enabled(group: group))
                .selectionDisabled(!enabled(group: group))
            }
            .environment(\.defaultMinListRowHeight, 40)
            .withAppRouter(router: router)
            .navigationBarTitle("", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.presentedSheet = .settings
                    } label: {
                        Image(systemName: "slider.vertical.3")
                    }
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
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.sheet(to: .scenes)
                    } label: {
                        Image(systemName: "wand.and.stars.inverse")
//                            .resizable()
//                            .foregroundStyle(.accent.gradient)
//                            .frame(width: 24, height: 24)
                    }
                    Spacer()
                    Button{
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.sheet(to: .search())
                    } label: {
                        Image(systemName: "magnifyingglass")
//                            .resizable()
//                            .foregroundStyle(.accent.gradient)
//                            .frame(width: 24, height: 24)
                    }
                    Spacer()
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.sheet(to: .browse())
                    } label: {
                        Image(systemName: "music.note.house")
//                            .resizable()
//                            .foregroundStyle(.accent.gradient)
//                            .frame(width: 24, height: 24)
                    }
                }
            }
//            .safeAreaInset(edge: .bottom) {
//                HStack(spacing: 24) {
//                    Spacer()
//                    if subscriptionService.subscription.isActive {
//                        Button {
//                            HapticManager.shared.fireHaptic(.buttonPress)
//                            router.sheet(to: .scenes)
//                        } label: {
//                            Image(systemName: "wand.and.stars.inverse")
//                                .resizable()
//                                .foregroundStyle(.accent.gradient)
//                                .frame(width: 24, height: 24)
//                        }
//                    }
//
//                    Button{
//                        HapticManager.shared.fireHaptic(.buttonPress)
//                        router.sheet(to: .search())
//                    } label: {
//                        Image(systemName: "sparkle.magnifyingglass")
//                            .resizable()
//                            .foregroundStyle(.accent.gradient)
//                            .frame(width: 24, height: 24)
//                    }
//                }
//                .padding()
//                .frame(maxWidth: .infinity)
//                .background(.thinMaterial)
//            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .safeAreaInset(edge: .top) {
            VStack {
                if alertService.alert.isShowing {
                    PillView()
                }

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
        .animation(.spring, value: sonosService.isSearching)
        .animation(.bouncy, value: sonosService.networkMonitorService.isConnected)
        .animation(.spring, value: sonosService.systemState.notFound)
        .animation(.spring, value: sonosService.systemState.permissionDenied)
        .animation(.spring, value: alertService.alert.isShowing)
        .animation(.interactiveSpring, value: sonosService.sorted)
    }

    private func enabled(group: GroupRoom) -> Bool {
        if subscriptionService.subscription.isActive { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
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
