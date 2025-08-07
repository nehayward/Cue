import Defaults
import CloudStorage
import SonosKit
import SubscriptionKit
import SwiftUI
import VibesDS
import Kingfisher

@main
struct TVApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    private var subscriptionService = SubscriptionService.shared
    private var sonosService = SonosService.shared

    @State private var isLoading: Bool = true
    @State private var showGroup: Bool = false
    @State private var showSettings: Bool = false
    @ObservedObject var value = TVPlayerView.Test()
    @AppStorage("disableScreenSaver") var disableScreenSaver = false

    public var sorted: [GroupRoom] {
        get {
            return sonosService.groups.sorted { g1, g2 in
                return g1.coordinatorRoom.name < g2.coordinatorRoom.name
            }
        }
        set {
            sonosService.groups = newValue
        }
    }
    
    init() {
        KingfisherManager.shared.defaultOptions = [
            .cacheSerializer(FormatIndicatedCacheSerializer.jpeg),
            .forceTransition,
            .transition(.fade(0.25)),
            .processor(DefaultImageProcessor.default), // Default is fast and non-blocking
            .scaleFactor(UIScreen.main.scale),   // Match screen scale to avoid extra work
            .cacheOriginalImage,                 // Cache original for future resizing
            .diskCacheExpiration(.days(7)),      // Longer-term disk caching
            .loadDiskFileSynchronously           // Improve first-load from disk (minor blocking risk)
        ]
        ImageCache.default.memoryStorage.config.totalCostLimit = 10 * 1024 * 1024
        ImageCache.default.diskStorage.config.sizeLimit = 20 * 1024 * 1024
        ImageCache.default.diskStorage.config.expiration = .days(1)
    }

    var body: some Scene {
        WindowGroup {
            @Bindable var sonosService = sonosService
            TabView(selection: $sonosService.selectedGroup) {
                ForEach(sorted) { group in
                    TVPlayerView(group: group, showGroup: $showGroup, showSettings: $showSettings, value: value)
                        .tabItem {
                            Label(group.nameWithCount, systemImage: "hifispeaker.fill")
                        }
                        .tag(group)
                }
            }
            .fullScreenCover(isPresented: $showGroup){
                if let group = sonosService.selectedGroup {
                    TVGroupScreen(coordinatorID: group.coordinatorID)
                } else {
                    if let group = sonosService.sorted.first {
                        TVGroupScreen(coordinatorID: group.coordinatorID)
                    }
                }
            }
            .fullScreenCover(isPresented: $showSettings){
                TVSettingsScreen()
            }
            .environment(sonosService)
            .environment(subscriptionService)
            .tabViewStyle(.tabBarOnly)
            .task {
                UIApplication.shared.isIdleTimerDisabled = disableScreenSaver
                isLoading = true
                guard let groups = try? await sonosService.getGroupsFast(), !groups.isEmpty else {
                    isLoading = false
                    return
                }
                sonosService.groups = groups
                sonosService.rooms = groups.flatMap(\.rooms)
                sonosService.selectedGroup = sorted.first
                sonosService.monitor()
                isLoading = false
            }
            .overlay {
                if sonosService.sorted.isEmpty, isLoading {
                    Text("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thickMaterial)
                        .transition(.opacity)
                }
                
                if !isLoading, sonosService.sorted.isEmpty {
                    TVOverviewView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                        .transition(.opacity)
                }
            }
        }
    }
    
}
