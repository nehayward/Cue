import CloudStorage
import RevenueCat
import RevenueCatUI
import SonosKit
import SubscriptionKit
import StoreKit
import SwiftUI
import WidgetKit

@main
struct ClicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.requestReview) var requestReview
    @Environment(\.liveActivityManager) var liveActivityManager

    @State private var router: Router = Router()
    @State private var subscriptionService = SubscriptionService.shared
    @State private var sonosService = SonosService.shared
    @State private var alertService = AlertService.shared

    @CloudStorage("com.clic.subscriptions") private var activeSubscription: Bool = false
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some Scene {
        WindowGroup {
            Group {
                if OSEnvironment.pad {
                    GroupListLargeScreen()
                } else {
                    DeviceListMainView()
                }
            }
            .environment(router)
            .environment(sonosService)
            .environment(subscriptionService)
            .environment(alertService)
            .onOpenURL(perform: handle)
            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
            .task {
                subscriptionService.monitorChanges()
            }
            .onAppear {
                // MARK: Remove when update is complete
                let updatedScenes = scenes.map { scene in
                    var updatedScene = scene
                    updatedScene.playableContent = nil
                    return updatedScene
                }
                scenes = updatedScenes
                
                SonosService.shared.groupsChanged = { groups in
                    guard subscriptionService.subscription.isActive else { return }
                    liveActivityManager.createActivity()
                }
            }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
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
                await liveActivityManager.refresh(type: .refresh)
            }

            Task {
                try? await subscriptionService.checkSubscription()
            }

            Task {
                try? await Task.sleep(for: .seconds(1))
                ReviewService.shared.askForRatingIfNeeded()
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
                await liveActivityManager.refresh(type: .refresh)
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

    private func handle(_ url: URL) {
        Task { @MainActor in
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            if components.host?.lowercased() == "subscribe" {
                router.presentedSheet = .paywall
                return
            }

            if components.host?.lowercased() == "search", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
                router.presentedSheet = nil

                if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                    if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                        router.path.removeAll()
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    } else if router.path.isEmpty {
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    }
                    router.presentedSheet = .search(group: group)
                    return
                }
                Task {
                    try await sonosService.fetch(useCache: true)
                    if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                        if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                            router.path.removeAll()
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        } else if router.path.isEmpty {
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        }
                        router.presentedSheet = .search(group: group)
                        return
                    }
                }
            }

            if components.host?.lowercased() == "device", let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
                router.presentedSheet = nil

                if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                    if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                        router.path.removeAll()
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    } else if router.path.isEmpty {
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    }
                    return
                }
                Task {
                    try await sonosService.fetch(useCache: true)
                    if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                        if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                            router.path.removeAll()
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        } else if router.path.isEmpty {
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        }
                        return
                    }
                }
            }

            if components.host?.lowercased() == "scene", let name = components.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
                guard let scene = scenes.first(where: { $0.name == name }) else { return }
                Task {
                    alertService.showAlert(with: "Running \(scene.name)")
                    try await sonosService.runScene(scene)
                }
            }

            if components.host?.lowercased() == "play", let paths = components.string?.split(separator: "/").map(String.init) {
                if paths.count < 3 {
                    return
                }
                guard let service = MusicService(service: paths[2]),
                      let type = ContentType(paths[3])
                else { return }

                let id = paths[4]

                let media = MediaContent(service: service, id: id, type: type, location: nil)
                router.presentedSheet = .playMedia(content: media)
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

}
