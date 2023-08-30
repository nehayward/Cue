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
    var superMember = SubscriptionService()
    var alertService = AlertService()

    let liveActivityManager: LiveActivityManager

    init() {
        liveActivityManager = LiveActivityManager(sonosService: sonosService)
    }

    var body: some Scene {
        WindowGroup {
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
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                Task {
                    print("Foreground")
                    do {
                        try await sonosService.updateGroupsCheckPlayback()
                        print("Tock", Date.now)
                    } catch {
                        print(error)
                        // Restart Search
                        sonosService.monitor()
                    }
                    if selected == nil {
                        guard let playingGroup = sonosService.groups.first(where: {$0.coordinatorRoom.isPlaying}) else { return }
                        alertService.showAlert(with: "Jumped to playing \(playingGroup.coordinatorRoom.name)")
                        selected = playingGroup.coordinatorID
                    }
                    sonosService.monitor()
//                    superMember.isEnabled = isEnabled
                }
            case .inactive:
                print("Inactive")
                WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
                sonosService.systemNotFound = false
                Task {
                    sonosService.sonosPulse.cancel()
                }
            case .background:
                sonosService.systemNotFound = false
            @unknown default:
                break
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
