import CloudStorage
import SwiftUI
import SonosKit
import SubscriptionKit
import RevenueCat
import RevenueCatUI

struct GroupListLargeScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(AlertService.self) var alertService: AlertService
    @Environment(Router.self) var router: Router

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var alertService = alertService
        @Bindable var sonosService = sonosService
        @Bindable var router = router

        NavigationSplitView {
            List ($sonosService.sorted, selection: $router.selection) { $group in
                Section {
                    VStack(spacing: 12) {
                        if group.tvMode {
                            TVModeViewCell(group: $group)
                        } else {
                            HStack(alignment: .top) {
                                ArtworkViewKing(group: $group)
                                    .frame(width: 72, height: 72)
                                ZoneView(group: $group)
                                Spacer()
                                MediaControlsView(group: $group)
                            }
                        }
                        VolumeControlView(group: $group, touchDelay: 0.05)
                            .frame(height: 24)
                    }
                    .tag(RouterDestination.player(groupID: group.coordinatorID))
                    .listRowBackground(group.coordinatorID == router.selection?.id ? Color(uiColor: .systemFill) : nil)
                    .foregroundStyle(.primary)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12))
                } header: {
                    Text(group.nameWithCount)
                        .fontDesign(.rounded)
                        .headerProminence(.increased)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
                .redacted(reason: enabled(group: group) ? [] : .placeholder)
                .disabled(!enabled(group: group))
                .selectionDisabled(!enabled(group: group))
            }
            .listStyle(.insetGrouped)
            .withAppRouter(router: router)
            .navigationBarTitle("", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.sheet(to: .settings)
                    } label: {
                        Image(systemName: "slider.vertical.3")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
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

                    if sonosService.systemState.notFound {
                        Button {
                            sonosService.monitor()
                        } label: {
                            Label("Discover Devices", systemImage: "waveform.badge.magnifyingglass")
                                .imageScale(.large)
                                .symbolEffect(.variableColor)
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
                            .buttonStyle(.plain)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    if subscriptionService.subscription.isActive {
                        Menu {
                            ForEach(scenes) { scene in
                                Button {
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    alertService.showAlert(with: "Running \(scene.name)")
                                    Task {
                                        try? await sonosService.runScene(scene)
                                    }
                                } label: {
                                    Text(scene.name)
                                        .tint(.red)
                                }
                            }
                            ControlGroup {
                                Button {
                                    router.sheet(to: .createScene)
                                } label: {
                                    Label("Create Scene", systemImage: "plus")
                                }
                            }
                        } label: {
                            Image(systemName: "bolt.circle.fill")
                                .font(.title)
                                .foregroundStyle(.accent)
                        }
                    }

                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.presentedSheet = .search()
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title)
                            .foregroundStyle(.accent)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .ignoresSafeArea()
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        } detail: {
            if let destination = router.selection {
                switch destination {
                case let .player(groupID):
                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                        LargePlayerView(group: $sonosService.sorted[group])
                            .navigationBarTitleDisplayMode(.inline)
                    } else {
                        Text("Group No Longer Available")
                            .onTapGesture {
                                router.selection = nil
                            }
                            .navigationBarTitleDisplayMode(.inline)
                    }
                default:
                    Text("Select a group")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack {
                if alertService.alert.isShowing {
                    PillView()
                }
                if !sonosService.networkMonitorService.isConnected {
                    Label {
                        Text("Connect to WiFi to find system")
                    } icon: {
                        Image(systemName: "wifi.slash")
                    }
                    .bold()
                    .padding()
                    .background {
                        Capsule()
                            .foregroundStyle(.thinMaterial)
                    }
                    .transition(.move(edge: .top).combined(with: .scale(0.8)))
                    .padding()
                    .offset(y: 50)
                }

                if sonosService.isSearching && sonosService.groups.isEmpty {
                    Label("Searching", systemImage: "waveform.badge.magnifyingglass")
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
        .animation(.interactiveSpring, value: sonosService.groups)
    }

    private func enabled(group: GroupRoom) -> Bool {
        if subscriptionService.subscription.isActive { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
    }
}

