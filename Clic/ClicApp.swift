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
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
//
//    // register initial UserDefaults values every launch
//    init() {
//        // Migrate Sonos Scenes
//        if OSEnvironment.versionInfo == "2023.3" {
//            guard !scenes.isEmpty else {
//                // no migration needed
//                return
//            }
//            let updatedScenes: [SonosScene] = scenes.map { scene in
//                return SonosScene(name: scene.name, rooms: scene.rooms, isActive: false)
//            }
//            scenes = updatedScenes
//            NSUbiquitousKeyValueStore.default.synchronize()
//            print("Migrated")
//        }
//    }

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
                .onOpenURL { url in
                    // TODO: Add Scene Search Handler
//                    selected = "RINCON_B8E937525BB001400"
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

            Task {
                try? await subscriptionService.checkSubscription()
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
            Task {
                await liveActivityManager?.refresh()
            }
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
