import SwiftUI
import SonosKit
import ActivityKit
import WidgetKit

@main
struct ClicApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State var selected: String?
    @State var showPaywall: Bool = false

    var sonosService = SonosService()
    var alertService = AlertService()

    @State var liveActivityManager: LiveActivityManager? = nil
    var superMember = SubscriptionService()

    var body: some Scene {
        WindowGroup {
//            TabView {
                ContentView(selected: $selected)
                    .environment(sonosService)
                    .environment(superMember)
                    .environment(alertService)
                    .sheet(isPresented: $showPaywall) {
                        PaywallScreen()
                            .environment(superMember)
                    }
                    .safeAreaInset(edge: .bottom) {
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
//                    .safeAreaInset(edge: .top) {
//                        Text("State: \(sonosService.state)")
//                            .fontDesign(.rounded)
//                            .fontWidth(.compressed)
//                            .foregroundStyle(Color.accentColor.gradient)
//                            .padding()
//                            .background(.thickMaterial)
//                            .clipShape(Capsule())
//                    }
                    .onAppear {
                        liveActivityManager = LiveActivityManager(sonosService: sonosService)
                    }
//                    .tabItem {
//                        Text("Normal")
//                    }
//                DebugView(sonosService: sonosService)
//                    .tabItem {
//                        Text("Debug")
//                    }
//                DebugView()
//                    .environment(sonosService)
//                    .tabItem {
//                        Text("Debug")
//                    }
//            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:

                    sonosService.monitor()

                    // MARK: Add back when monitoring is fixed
//                    do {
//                        try await sonosService.updateGroupsCheckPlayback()
//                        print("Tock", Date.now)
//                    } catch {
//                        print(error)
//                        // Restart Search
//                    }
//                    if selected == nil {
//                        selected = sonosService.groups.first(where: { room in
//                            room.coordinatorRoom.isPlaying
//                        })?.coordinatorID
//
//                        alertService.showAlert(with: "Jumped to playing")
//                    }
                    //                    superMember.isEnabled = isEnabled

            case .inactive:
                print("Inactive")
                WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")

            case .background:
                print("Background")
                sonosService.systemNotFound = false
                Task {
                    sonosService.sonosPulse.cancel()
                }
            @unknown default:
                break
            }
        }
        .onChange(of: sonosService.groups.map(\.coordinatorRoom.isPlaying)) {
            liveActivityManager?.createActivity(with: sonosService.groups)
        }
        .onChange(of: superMember.isEnabled) {
//            isEnabled = superMember.isEnabled
        }



//        .backgroundTask(.appRefresh(UUID().uuidString)) { action in
//            LiveActivityManager.shared.refresh()
//        }
    }
}
