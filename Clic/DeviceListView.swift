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
                    Button {
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    } label: {
                        VStack(spacing: 12) {
                            if group.TVMode {
                                TVModeViewCell(group: $group)
                            } else {
                                HStack(alignment: .top) {
                                    ArtworkView(track: $group.coordinatorRoom.track)
                                        .frame(width: 72, height: 72)
                                    ZoneView(group: $group)
                                    Spacer()
                                    MediaControlsView(group: $group)
                                }
                            }
                            VolumeControlView(group: $group, touchDelay: 0.05)
                                .frame(height: 24)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: group.coordinatorRoom.track.TVMode ? 12 : 10, trailing: 12))
                    .dropDestinationPlay(on: group)
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
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    if subscriptionService.subscription.isActive {
                        Button {
                            router.sheet(to: .scenes)
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
        }
        .safeAreaInset(edge: .top) {
            VStack {
                if alertService.alert.isShowing {
                    PillView()
                }

                if !sonosService.networkMonitorService.isConnected {
                    Label("Can't find System, Connect to Wi-Fi", systemImage: "wifi.slash")
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
        .animation(.interactiveSpring, value: sonosService.groups)
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
}
