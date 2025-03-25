import Observation
import Kingfisher
import Defaults
import SwiftUI
import SonosKit
import SonosKitMini
import WidgetKit
import CloudStorage

@main
struct WatchApp: App {
    @Environment(\.scenePhase) var scenePhase
    @CloudStorage(CloudKeys.hasSubscription) var activeSubscription: Bool = false
    @CloudStorage("com.clic.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true

    private var sonosService = SonosMiniService.shared
    private var router: Router = .main
    private var popover = Popover.shared

    var body: some Scene {
        WindowGroup {
            @Bindable var router = router
            DeviceListView(activeSubscription: $activeSubscription, selected: $router.selectedID)
                .environment(router)
                .withEnvironments()
                .onAppear {
                    configureImageStorage()
                }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
    }
    
    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        if scenePhase == .active {
            Task {
                if autoLaunchNowPlaying, router.selectedID == nil {
                    let id = await sonosService.getNowPlayingID()
                    if router.selectedID == nil, let id {
                        withAnimation {
                            router.selectedID = id
                        }
                    }
                }
                do {
                    try await sonosService.loadWatch(useCache: true)
                } catch {
                    try await sonosService.loadWatch(useCache: false)
                    print(error)
                }
            }
        }
    }
    
    private func configureImageStorage() {
        ImageCache.default.memoryStorage.config.totalCostLimit = 24 * 1024 * 1024
    }
}
