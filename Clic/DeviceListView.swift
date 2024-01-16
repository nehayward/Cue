import CloudStorage
import SwiftUI
import SonosKit
import SubscriptionKit
import RevenueCat
import RevenueCatUI

struct DeviceListMainView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(AlertService.self) var alertService: AlertService
    @Environment(RouterPath.self) var router: RouterPath

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var alertService = alertService
        @Bindable var sonosService = sonosService
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            List ($sonosService.sorted) { $group in
                Section {
                    Button {
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    } label: {
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
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: group.tvMode ? 12 : 10, trailing: 12))
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
            .safeAreaInset(edge: .bottom) {
                VStack {
                    if sonosService.permissionsDenied {
                        Button {
                            // MARK: Settings Action
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Local Network Permission Needed")
                                .padding()
                                .background {
                                    Capsule()
                                        .foregroundStyle(.thinMaterial)
                                }
                        }
                        .transition(.move(edge: .bottom).combined(with: .scale(0.8)))
                        .padding()
                    }

                    if sonosService.systemNotFound {
                        Button {
                            sonosService.monitor()
                        } label: {
                            Text("Discover")
                                .bold()
                                .padding()
                                .background {
                                    Capsule()
                                        .foregroundStyle(.thinMaterial)
                                }
                        }
                        .transition(.scale)
                    }

                    if !subscriptionService.subscription.isActive {
                        PaywallButtonView()
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                    }

                    HStack {
                        Spacer()
                        if subscriptionService.subscription.isActive {
                            Menu {
                                ForEach(scenes) { scene in
                                    Button {
                                        Task {
                                            try? await sonosService.runScene(scene)
                                        }
                                    } label: {
                                        Text(scene.name)
                                            .tint(.red)
                                    }
                                }
                            } label: {
                                Image(systemName: "bolt.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.accent)
                            }
                            .buttonStyle(.haptic)
                        }

                        Button {
                            router.presentedSheet = .search()
                        } label: {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.title)
                                .foregroundStyle(.accent)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .buttonStyle(.haptic)
                    }
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity)
                    .background(.bar)

//                    if !sonosService.groups.isEmpty && subscriptionService.subscription.isActive && !scenes.isEmpty {
//                        SceneView()
//                            .transition(.offset(y: 100))
//                    }
//                    HStack {
//                        Spacer()
//                        Button {
////                            show = true
//                        } label: {
//                            Text("Search")
//                                .bold()
//                                .padding()
//                                .background {
//                                    Capsule()
//                                        .foregroundStyle(.thinMaterial)
//                                }
//                        }
//                        .buttonStyle(.haptic)
//                        .bold()
//                        .buttonStyle(.borderedProminent)
//                    }
//                    .background(.clear)
//                    .scrollTargetLayout()
//                    .fontDesign(.rounded)
//                    .fontWeight(.bold)
                }
            }
        }

//        .onChange(of: sonosService.sorted.count) {
//            if let currentPath = router.path.last {
//                switch currentPath {
//                case .player(let group):
//                    let group = sonos
//                }
//                router.path.removeAll()
//                router.navigate(to: .player(group: group))
//            }

//            guard !OSEnvironment.pad else { return }
//            if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected.id }) {
//                sonosService.selectedGroup = sonosService.sorted[index]
//            } else {
//                sonosService.selectedGroup = nil
//                selected = nil
//            }
            
//        }
        .animation(.spring, value: sonosService.isSearching)
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
        .animation(.bouncy, value: sonosService.networkMonitorService.isConnected)
        .animation(.spring, value: sonosService.systemNotFound)
        .animation(.spring, value: sonosService.permissionsDenied)
        .animation(.spring, value: alertService.alert.isShowing)
        .animation(.interactiveSpring, value: sonosService.groups)
        .task {
            guard OSEnvironment.isPreviews else { return }
            sonosService.monitor()
        }
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
        .environment(RouterPath())
}


#if DEBUG
#Preview("Appstore Screens") {
    DeviceListMainView()
        .screenshot(name: "Appstore")
        .colorScheme(.dark)
        .environment(SonosService.shared)
        .environment(SubscriptionService.shared)
        .environment(AlertService.shared)
        .environment(RouterPath())
}
#endif
