import ActivityKit
import CloudStorage
import RevenueCat
import SonosKit
import SubscriptionKit
import SwiftUI
import WidgetKit

@main
struct ClicApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State private var selected: String?
    @State private var liveActivityManager: LiveActivityManager? = nil
    @State private var subscriptionService = SubscriptionService()
    @State private var sonosService = SonosService()
    @State private var alertService = AlertService()
    @CloudStorage("com.clic.subscriptions") private var activeSubscription: Bool = false

    var body: some Scene {
        WindowGroup {
            DeviceListMainView(selected: $selected)
                .environment(sonosService)
                .environment(subscriptionService)
                .environment(alertService)
                .task {
                    liveActivityManager = LiveActivityManager(sonosService: sonosService)
                    subscriptionService.monitorChanges()
                }
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["Super"] == "TRUE" {
                        subscriptionService.subscription = Subscription(isActive: true)
//                        subscriptionService.subscription = .notActive
                    }
//                    sonosService.systemNotFound = true
                    #endif
                }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
        .onChange(of: sonosService.groups.map(\.coordinatorRoom.isPlaying)) {
            guard subscriptionService.subscription.isActive else { return }
            Task {
                await liveActivityManager?.createActivity(with: sonosService.groups)
            }
        }
        .onChange(of: subscriptionService.subscription, initial: true) { oldValue, newValue in
            activeSubscription =  newValue.isActive
        }
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            sonosService.monitor()
            if !subscriptionService.subscription.isActive {
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
