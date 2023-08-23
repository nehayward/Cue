import SwiftUI
import SonosKit
import ActivityKit
import WidgetKit

@main
struct ClicApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State var selected: String?
    @State var showPaywall: Bool = false

    @AppStorage("membership") var isEnabled = false

    var sonosService = SonosService()
    var superMember = SubscriptionService()
    let liveActivityManager: LiveActivityManager

    init() {
        liveActivityManager = LiveActivityManager(sonosService: sonosService)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(selected: $selected)
                .environment(sonosService)
                .environment(superMember)
                .task {
                    sonosService.monitor()
                    await superMember.setup()
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallScreen()
                        .environment(superMember)
                }
                .overlay(alignment: .bottom) {
                    if !superMember.isEnabled {
                        Button {
                            showPaywall = true
                        } label: {
                            Text("Show all devices (\(sonosService.groups.count))")
                                .fontDesign(.rounded)
                                .fontWidth(.compressed)
                                .foregroundStyle(Color.accentColor.gradient)
                                .padding()
                                .background(.thickMaterial)
                                .clipShape(Capsule())
                        }
                    }
                }
                .overlay {
                        VStack {
                            Text(sonosService.networkMonitorService.isConnected ? "Connected" : "Disconnect")
                            Text(!sonosService.monitorTask.isCancelled ? "Running" : "Cancelled")
                                .bold()
                            Spacer()
                        }
                        .ignoresSafeArea()
                        .padding(.top, 30)
                }
                .safeAreaInset(edge: .bottom) {
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
                            Text("No System Found. Search")
                                .padding()
                                .background {
                                    Capsule()
                                        .foregroundStyle(.thinMaterial)
                                }
                        }
                        .transition(.move(edge: .bottom).combined(with: .scale(0.8)))
                        .padding()
                    }

                    if !sonosService.networkMonitorService.isConnected {
                        Text("Please connect to WiFi to find system")
                            .padding()
                            .background {
                                Capsule()
                                    .foregroundStyle(.thinMaterial)
                            }
                            .transition(.move(edge: .bottom).combined(with: .scale(0.8)))
                            .padding()
                    }
                }
                .animation(.bouncy, value: sonosService.networkMonitorService.isConnected)
                .animation(.spring, value: sonosService.systemNotFound)
                .animation(.spring, value: sonosService.permissionsDenied)
                .onAppear {
                    let thumbImage = UIImage()
                    UISlider.appearance().setThumbImage(thumbImage, for: .normal)
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
                sonosService.monitorTask.cancel()
            }

            if scenePhase == .active {
                print("Foreground")
                Task {
                    try await Task.sleep(for: .milliseconds(300))
                    if selected == nil {
                        selected = sonosService.groups.first(where: { room in
                            room.coordinatorRoom.isPlaying
                        })?.coordinatorID
                    }
                }
                sonosService.monitor()

//                if !sonosService.pulseIsRunning {
//                }
////                superMember.isEnabled = isEnabled
//
//                Task {
//                    await sonosService.pulse()
//                }
            }
        }
        .onChange(of: sonosService.groups.map(\.coordinatorRoom.isPlaying)) {
            liveActivityManager.createActivity(with: sonosService.groups)
        }
        .onChange(of: superMember.isEnabled) {
//            isEnabled = superMember.isEnabled
        }



//        .backgroundTask(.appRefresh(UUID().uuidString)) { action in
//            LiveActivityManager.shared.refresh()
//        }
    }
}
