import Observation
import Kingfisher
import Defaults
import SwiftUI
import SonosKitMini
import WidgetKit
import CloudStorage

@main
struct WatchApp: App {
    @Environment(\.scenePhase) var scenePhase
    #if DEBUG
    @CloudStorage(CloudKeys.hasSubscription) var activeSubscription: Bool = true
    #else
    @CloudStorage(CloudKeys.hasSubscription) var activeSubscription: Bool = false
    #endif
    @CloudStorage("com.cue.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true

    private var sonosService = SonosMiniService.shared
    private var popover = Popover.shared
    
    @State private var router: Router = .main

    var body: some Scene {
        WindowGroup {
            DeviceListView(activeSubscription: $activeSubscription, selected: $router.selectedID)
                .environment(router)
                .withEnvironments()
                .onAppear {
                    configureImageStorage()
                    configurePeriodicCleanup()
                }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
    }
    
    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        if scenePhase == .active {
            // Clean expired image caches to prevent memory growth over days
            ImageCache.default.cleanExpiredMemoryCache()
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
                    try? await sonosService.loadWatch(useCache: false)
                }
            }
        } else if scenePhase == .background {
            // Disconnect WebSocket connections when backgrounded to free memory.
            // They will be re-established when the app becomes active again.
            Task {
                await sonosService.streamingService.disconnectAll()
            }
        }
    }
    
    private func configurePeriodicCleanup() {
        sonosService.onPeriodicCleanup = {
            ImageCache.default.clearMemoryCache()
            ImageCache.default.cleanExpiredDiskCache()
        }
        sonosService.startPeriodicCleanup()
    }

    private func configureImageStorage() {
        KingfisherManager.shared.defaultOptions = [
            .cacheSerializer(FormatIndicatedCacheSerializer.jpeg),
            .processor(DefaultImageProcessor.default),
            .scaleFactor(WKInterfaceDevice.current().screenScale),
            .diskCacheExpiration(.days(1)),
            .memoryCacheExpiration(.seconds(300)) // 5 min memory cache, auto-cleaned
        ]
        ImageCache.default.memoryStorage.config.countLimit = 5
        ImageCache.default.memoryStorage.config.totalCostLimit = 5 * 1024 * 1024 // 5MB max memory
        ImageCache.default.diskStorage.config.sizeLimit = 10 * 1024 * 1024 // 10MB disk
        ImageCache.default.diskStorage.config.expiration = .days(1)
        // Clean expired entries on launch
        ImageCache.default.cleanExpiredMemoryCache()
        ImageCache.default.cleanExpiredDiskCache()
    }
}
