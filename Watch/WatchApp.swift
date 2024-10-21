import Observation
import Nuke
import SwiftUI
import SonosKit
import WidgetKit
import CloudStorage

@main
struct WatchApp: App {
    @Environment(\.scenePhase) var scenePhase
    @CloudStorage("com.clic.subscriptions") var activeSubscription: Bool = false

    @State private var router: Router = .main
    @State private var sonosService = SonosService.shared
    @State private var popover = Popover.shared

    @CloudStorage("com.clic.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true
    @CloudStorage("com.clic.plexToken") var plexToken: String = ""

    var body: some Scene {
        WindowGroup {
            DeviceListView(activeSubscription: $activeSubscription, selected: $router.selectedID)
                .environment(router)
                .withEnvironments()
                .onChange(of: router.selectedID) {
                    print("Update current")
                    if let selected = router.selectedID, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                        sonosService.selectedGroup = sonosService.sorted[index]
                    }
                }
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["Super"]?.lowercased() == "true" {
                        activeSubscription = true
                    }
                    #endif
                    configureNuke()
                    
                    if !plexToken.isEmpty {
                        UserDefaults.standard.set(plexToken, forKey: "com.clic.plexToken")
                    }
                }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
    }
    
    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            sonosService.monitor()
            if autoLaunchNowPlaying {
                Task {
                    try? await sonosService.updateGroupsCheckPlayback()
                    if router.selectedID == nil {
                        let playingGroups = sonosService.groups.filter(\.coordinatorRoom.isPlaying)
                        if playingGroups.count == 1, let groupPlaying = playingGroups.first {
                            Task { @MainActor in
                                router.selectedID = groupPlaying.coordinatorID
                            }
                        }
                    }
                }
            }
            
            if sonosService.selectedGroup != nil {
                Task {
                    try? await sonosService.load(useCache: true)
                }
            }
        case .inactive:
            print("Inactive")
        case .background:
            print("Background")
            Task {
                sonosService.sonosPulse.cancel()
                sonosService.watcher.cancel()
            }
        @unknown default:
            break
        }
    }
    
    private func configureNuke() {
        let pipeline = ImagePipeline {
            $0.imageCache = ImageCache.shared
            $0.dataCache = try? DataCache(name: "com.clic.imageCache")
            $0.dataCachePolicy = .automatic
            let dataLoader: DataLoader = {
                let config = URLSessionConfiguration.default
                config.urlCache = nil
                return DataLoader(configuration: config)
            }()

            $0.dataLoader = dataLoader
        }
        ImagePipeline.shared = pipeline
    }
}
