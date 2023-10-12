import SwiftUI
import SonosKit
import ActivityKit
import WidgetKit
import RevenueCat
import SubscriptionKit
import CloudStorage

@main
struct ClicApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State private var selected: String?
    @State private var liveActivityManager: LiveActivityManager? = nil
    @State private var subscriptionService = SubscriptionService()
    @State private var sonosService = SonosService()
    @State private var alertService = AlertService()

    var body: some Scene {
        WindowGroup {
            DeviceListView(selected: $selected)
                .environment(sonosService)
                .environment(subscriptionService)
                .environment(alertService)
                .task {
                    liveActivityManager = LiveActivityManager(sonosService: sonosService)
                    subscriptionService.monitorChanges()
                }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
        .onChange(of: sonosService.groups.map(\.coordinatorRoom.isPlaying)) {
            guard subscriptionService.current.subscription.isActive else { return }
            Task {
                await liveActivityManager?.createActivity(with: sonosService.groups)
            }
        }
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            sonosService.monitor()
            if !subscriptionService.current.subscription.isActive {
                return
            }
            
            Task {
                await liveActivityManager?.refresh()
            }

//            // MARK: Add back when monitoring is fixed
//            Task { @MainActor in
//                try? await sonosService.updateGroupsCheckPlayback()
//
//                if selected == nil {
//                    let playingGroups = sonosService.groups.filter(\.coordinatorRoom.isPlaying)
//                    if playingGroups.count == 1, let groupPlaying = playingGroups.first {
//                        try await Task.sleep(for: .milliseconds(200))
//                        alertService.showAlert(with: "Jumped to \(groupPlaying.coordinatorRoom.name)")
//                        selected = groupPlaying.coordinatorID
//                    }
//                }
//            }
        case .inactive:
            print("Inactive")
            WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
        case .background:
            print("Background")
            Task {
                sonosService.sonosPulse.cancel()
            }
        @unknown default:
            break
        }
    }
}
