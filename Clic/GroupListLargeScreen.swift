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
    @Environment(RouterPath.self) var router: RouterPath

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var alertService = alertService
        @Bindable var sonosService = sonosService
        @Bindable var router = router

        NavigationSplitView {
            List ($sonosService.sorted) { $group in
                Section {
                    Button {
                        router.path.removeAll()
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
                    .tint(.primary)
                    //                    .accentColor(group.coordinatorID == selected?.id ? .primary : .accent)
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
                            Text("Search")
                                .bold()
                                .padding()
                                .background {
                                    Capsule()
                                        .foregroundStyle(.thinMaterial)
                                }
                        }
                        .transition(.scale)
                    }

                    if !sonosService.groups.isEmpty && subscriptionService.subscription.isActive && !scenes.isEmpty {
                        SceneView()
                            .transition(.offset(y: 100))
                    }

                    if !subscriptionService.subscription.isActive {
                        Button {
                            router.presentedSheet = .paywall
                        } label: {
                            Text("Show all devices (\(sonosService.groups.count))")
                                .fontDesign(.rounded)
                                .bold()
                                .foregroundStyle(Color.accentColor.gradient)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(.thickMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding()
                                .shadow(radius: 16, x: 0, y: 2)
                        }
                    }
                }
            }
        } detail: {
            NavigationStack {
                if let destination = router.path.first {
                    switch destination {
                    case let .player(groupID):
                        if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                            LargePlayerView(group: $sonosService.sorted[group])
                        } else {
                            Text("Group No Longer Available")
                                .onTapGesture {
                                    router.path.removeAll()
                                }
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
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
        .onAppear {
            let thumbImage = UIImage()
            UISlider.appearance().setThumbImage(thumbImage, for: .normal)
        }
        .animation(.interactiveSpring, value: sonosService.groups)
        .task {
            guard OSEnvironment.isPreviews else { return }
            sonosService.monitor()
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func enabled(group: GroupRoom) -> Bool {
        if subscriptionService.subscription.isActive { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
    }
}

