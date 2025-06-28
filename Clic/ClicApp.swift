import Analytics
import Defaults
import Nuke
import CloudStorage
import RevenueCat
import RevenueCatUI
import SonosKit
import SubscriptionKit
import MusicKit
import MusicSearchKit
import StoreKit
import SwiftUI
import TipKit
import CoreSpotlight
#if canImport(WidgetKit)
import WidgetKit
#endif
@main
struct ClicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.liveActivityManager) var liveActivityManager

    @State private var router: Router = Router.main
    @State private var subscriptionService = SubscriptionService.shared
    @State private var sonosService = SonosService.shared
    @State private var alertService = AlertService.shared
    @State private var musicSearchService = MusicSearchService.shared
    @State private var playlistContainer = PlaylistContainer.shared
    private var playHistoryService = PlayHistoryService.shared
    private var miniPlayerManager = MiniPlayerManger.shared

    @CloudStorage(CloudKeys.hasSubscription) private var activeSubscription: Bool = false
    @CloudStorage(CloudKeys.scenes) var scenes: [SonosScene] = []
    
    @AppStorage(GroupStorageKeys.hasOnboarded, store: GroupStorageKeys.storage) private var hasOnboarded: Bool = false
    @AppStorage("ClicMiniEnabled") private var isMenuBarAppEnabled: Bool = true
    @AppStorage(Defaults.AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(Defaults.AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false

    @State var selectedID: String?
    @State private var previousCount: Int = 0
    
#if targetEnvironment(macCatalyst)
    private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared
#endif

    var body: some Scene {
        WindowGroup {
            VStack {
                if OSEnvironment.pad || UIDevice.current.userInterfaceIdiom == .vision {
                    HStack {
                        SidebarSplitView {
                            ListViewLarge(selected: $selectedID)
                            ContainerLargePlayerView(id: $selectedID)
                            DeviceListMainView()    
                        }
#if !os(visionOS)
                        .withInspector(inspectorDestination: $router.inspectorSheet)
                        .ignoresSafeArea()
#endif
#if os(visionOS)
                        .ornament(visibility: .visible, attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
                            Group {
                                switch router.inspectorSheet {
                                case let .search(group):
                                    SearchScreen {
                                        router.inspectorSheet = nil
                                    }
                                    .environment(SelectedGroupService(group: group))
                                case let .queue(group):
                                    QueueScreen(closeInspector: {
                                        router.inspectorSheet = nil
                                    }, group: group)
                                case let .browse(group):
                                    @State var selectedGroupService = SelectedGroupService(group: group)
                                    BrowseScreen {
                                        router.inspectorSheet = nil
                                    }
                                    .environment(selectedGroupService)
                                default:
                                    EmptyView()
                                        .onAppear {
                                            router.inspectorSheet = nil
                                        }
                                }
                            }
                            .glassBackgroundEffect()
                            .frame(minWidth: 400, minHeight: 800)
                            .offset(x: router.inspectorSheet != nil ? 0 : -400)
                            .offset(z: router.inspectorSheet != nil ? 0 : -64)
                            .opacity(router.inspectorSheet != nil ? 1 : 0)
                            .animation(.spring, value: router.inspectorSheet)
                            .withEnvironments()
                        }
#endif
                    }
                    .withAlert()
                    .animation(.spring, value: alertService.alert.isShowing)
                } else {
                    DeviceListMainView()
                }
            }
            .environment(router)
            .environment(sonosService)
            .environment(subscriptionService)
            .environment(alertService)
            .environment(musicSearchService)
            .environment(playlistContainer)
            .environment(playHistoryService)
            .environment(miniPlayerManager)
            .onOpenURL(perform: handle)
            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
            .onAppear {
                // MARK: Move for accent color fix
                SubscriptionService.shared.initialize(key: CloudKeys.hasSubscription)
                Analytics.shared.configure(token: "343f1efbe07acecdefdcd6f71f351673", userID: SubscriptionService.shared.userID)

                // Check MusicService
                if let musicService = UserDefaults.standard.string(forKey: AppStorageKeys.mediaService) {
                    Analytics.shared.setSelection(metadata: ["MusicService": musicService])
                }

                Task { @MainActor in
                    try? await SubscriptionService.shared.checkSubscription()
                }

                SonosService.shared.groupsChanged = { groups in
                    guard subscriptionService.subscription.isActive else { return }
                    liveActivityManager.createActivity()
                }

                SubscriptionService.shared.subscriptionUpdated = { subscription in
                    activeSubscription = subscription.isActive
#if canImport(WidgetKit)
                    WidgetCenter.shared.reloadAllTimelines()
#endif
                }
                
                try? Tips.configure(
                    [
                        .displayFrequency(.immediate)
                    ]
                )
                // MARK: For Debug
//                Tips.showTipsForTesting([AppTip.self])
                
                // MARK: Configure NukeUI
                configureNuke()
                
                // TODO: Add onboard
//                if !hasOnboarded {
//                    print(SheetDestination.onboard.id)
//                    router.sheet(to: .onboard)
//                }
                
               // TODO: Add Feature to force dark mode
//                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
//                    windowScene.windows.forEach { window in
//                        window.overrideUserInterfaceStyle = .dark
//                    }
//                }
                // Update SMAppService registration with proper error handling
#if targetEnvironment(macCatalyst)
                if isMenuBarAppEnabled {
                    menuAppLaunchAtLoginManager.macUtils?.openClicMiniApp()
                }
#endif
            }
#if targetEnvironment(macCatalyst)
            .frame(minWidth: 800, minHeight: 500)
#endif
            .fontDesign(.rounded)
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let userInfo = activity.userInfo, let itemIdentifier = userInfo[CSSearchableItemActivityIdentifier] as? String else {
                    return
                }
                if itemIdentifier.starts(with: "SonosDeviceEntity/") {
                    let deviceID = itemIdentifier.replacingOccurrences(of: "SonosDeviceEntity/", with: "")
                    
                    Task {
                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: deviceID) else { return }
                        if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                            if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                                router.path.removeAll()
                                router.navigate(to: .player(groupID: group.coordinatorID))
                            } else if router.path.isEmpty {
                                router.navigate(to: .player(groupID: group.coordinatorID))
                            }
                        } else {
                            selectedID = group.coordinatorID
                        }
                    }
                }
            }
            .preferredColorScheme(colorScheme.scheme)
        }
        .windowResizability(.contentMinSize)
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
        .onChange(of: subscriptionService.subscription, initial: true) { oldValue, newValue in
            activeSubscription =  newValue.isActive
        }
        .onChange(of: selectedID) { old, new in
            if let id = selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                if let sheet = router.inspectorSheet, sheet.id == "search" {
                    router.inspectorSheet = .search(group: sonosService.sorted[group])
                } else if let sheet = router.inspectorSheet, sheet.id == "queue" {
                    router.inspectorSheet = .queue(group: $sonosService.sorted[group])
                } else if let sheet = router.inspectorSheet, sheet.id == "browse" {
                    router.inspectorSheet = .browse(group: sonosService.sorted[group])
                }
            }
        }
        .onChange(of: sonosService.groups) { old, new in
            if sonosService.rooms.count == previousCount {
                return
            }

            Analytics.shared.track(.numberOfDevices, with: ["Device Count" : sonosService.rooms.count,
                                                            "Subscriber": subscriptionService.subscription.isActive])
            previousCount = sonosService.rooms.count
        }
        .onChange(of: sonosService.sortedRooms) {
            if #available(iOS 18.0, *) {
                Task {
                    try? await CSSearchableIndex.default().deleteAllSearchableItems()
                    try? await CSSearchableIndex.default().indexAppEntities(
                        sonosService.sortedRooms.map { SonosDeviceEntity(id: $0.id, ip: $0.ip, name: $0.name)}
                    )
                }
            }
        }
        .commands {
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                Divider()
                Button {
                    if let id = selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                        if router.inspectorSheet != .search(group: sonosService.sorted[group]) {
                            router.inspectorSheet = .search(group: sonosService.sorted[group])
                        } else {
                            router.inspectorSheet = nil
                        }
                    }
                } label: {
                    Label("\(router.inspectorSheet?.id ?? "" == "search" ? "Hide" : "Show") Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("s", modifiers: [])
                
                Button {
                    if let id = selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                        if router.inspectorSheet != .browse(group: sonosService.sorted[group]) {
                            router.inspectorSheet = .browse(group: sonosService.sorted[group])
                        } else {
                            router.inspectorSheet = nil
                        }
                    }
                } label: {
                    Label("\(router.inspectorSheet?.id ?? "" == "browse" ? "Hide" : "Show") Browse", systemImage: "house.fill")
                }
                .keyboardShortcut("b", modifiers: [])

                Button {
                    if let id = selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                        if router.inspectorSheet != .queue(group: $sonosService.sorted[group]) {
                            router.inspectorSheet = .queue(group: $sonosService.sorted[group])
                        } else {
                            router.inspectorSheet = nil
                        }
                    }
                } label: {
                    Label("\(router.inspectorSheet?.id ?? "" == "queue" ? "Hide" : "Show") Queue", systemImage: "list.dash")
                }
                .keyboardShortcut("q", modifiers: [])
            }
            CommandMenu("Playback") {
                Button{
                    Task {
                        if let id = selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                            if group.coordinatorRoom.isPlaying {
                                HapticManager.shared.fireHaptic(.selection)
                                await sonosService.pause(ip: group.coordinatorRoom.ip)
                            } else {
                                HapticManager.shared.fireHaptic(.selection)
                                await sonosService.play(ip: group.coordinatorRoom.ip)
                            }
                        }
                    }
                } label: {
                    if let id = selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                        Label {
                            Text("\(group.coordinatorRoom.isPlaying ? "Pause" : "Play") \(group.nameWithCount)")
                        } icon: {
                            Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                        }
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
//        guard hasOnboarded else { return }
        switch scenePhase {
        case .active:
            sonosService.monitor()
            Task {
                try await Task.sleep(for: .milliseconds(300))
                sonosService.onServerListening()
            }
            
            if !subscriptionService.subscription.isActive {
                return
            }
            
            if speedLaunchNowPlaying {
                Task {
                    if sonosService.groups.isEmpty {
                        try? await sonosService.updateGroups()
                    }
                    try? await sonosService.updateGroupsCheckPlayback()
                    handle(URL(string: "clic://playing")!)
                }
            }

            Task {
                await liveActivityManager.refresh()

                for group in sonosService.groups {
                    if !group.coordinatorRoom.isPlaying {
                        await liveActivityManager.stop(id: group.coordinatorRoom.id)
                    }
                }
            }

            Task {
                try? await subscriptionService.checkSubscription()
            }

            Task {
                try? await Task.sleep(for: .seconds(1))
                ReviewCoordinator.shared.requestReview()
            }
        case .inactive:
            print("Inactive")
#if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
#endif
            Task {
                await liveActivityManager.refresh()
            }
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

    private func handle(_ url: URL) {
        Task { @MainActor in
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            
            if sonosService.groups.isEmpty {
                try? await sonosService.updateGroups()
            }
            
            if components.host?.lowercased() == "playing" {
                let playingGroups = sonosService.groups.filter({ $0.coordinatorRoom.isPlaying || $0.TVMode })
                guard let group = playingGroups.first else {
                    return
                }
                
                Task {
                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                        if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                            router.path.removeAll()
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        } else if router.path.isEmpty {
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        }
                    } else {
                        selectedID = group.coordinatorID
                    }
                }
                return
            }
            
            if components.host?.lowercased() == "alarms" {
                router.presentedSheet = .settings(destination: .alarms)
                return
            }
            
            if components.host?.lowercased() == "subscribe" {
                router.presentedSheet = .paywall
                return
            }
            
            if components.host?.lowercased() == "search", url.pathComponents.contains("favorites") {
                // Navigate to favorite search
                router.path.removeAll()
                router.presentedSheet = .favorites
                return
            }

            if components.host?.lowercased() == "search", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
                router.presentedSheet = nil
                

                guard let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) else {
                    Task {
                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
                            return
                        }
                        if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                            if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                                router.path.removeAll()
                                router.navigate(to: .player(groupID: group.coordinatorID))
                            } else if router.path.isEmpty {
                                router.navigate(to: .player(groupID: group.coordinatorID))
                            }
                            router.presentedSheet = .search(group: group)
                        } else {
                            selectedID = group.coordinatorID
                            router.inspectorSheet = .search(group: group)
                        }
                    }
                    return
                }
                
                if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                    if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                        router.path.removeAll()
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    } else if router.path.isEmpty {
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    }
                    router.presentedSheet = .search(group: group)
                } else {
                    selectedID = group.coordinatorID
                    router.inspectorSheet = .search(group: group)
                }
                return
            }

            if components.host?.lowercased() == "device", let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
                router.presentedSheet = nil

                guard let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) else {
                    Task {
                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
                            return
                        }
                        if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                            if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                                router.path.removeAll()
                                router.navigate(to: .player(groupID: group.coordinatorID))
                            } else if router.path.isEmpty {
                                router.navigate(to: .player(groupID: group.coordinatorID))
                            }
                        } else {
                            selectedID = group.coordinatorID
                        }
                    }
                    return
                }
                
                if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                    if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                        router.path.removeAll()
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    } else if router.path.isEmpty {
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    }
                } else {
                    selectedID = group.coordinatorID
                }
            }

            if components.host?.lowercased() == "scene", let name = components.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
                guard let scene = scenes.first(where: { $0.name == name }) else { return }
                Task {
                    alertService.showAlert(with: "Running \(scene.name)")
                    try await sonosService.runScene(scene)
                }
            }

            if components.host?.lowercased() == "play", let paths = components.string?.split(separator: "/").map(String.init), let url = components.url {
                if paths.count < 3 {
                    return
                }
                router.sheet(to: .playMedia(url: url))
            }

            if components.host?.lowercased() == "group", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
                router.presentedSheet = nil
                if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                        if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                            router.path.removeAll()
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        } else if router.path.isEmpty {
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        }
                        router.presentedSheet = .groupScreen(group: group)
                    } else {
                        selectedID = group.coordinatorID
                        router.presentedSheet = .groupScreen(group: group)
                    }
                    return
                }
                Task {
                    try await sonosService.load(useCache: true)
                    if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                        if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                            if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                                router.path.removeAll()
                                router.navigate(to: .player(groupID: group.coordinatorID))
                            } else if router.path.isEmpty {
                                router.navigate(to: .player(groupID: group.coordinatorID))
                            }
                            router.presentedSheet = .groupScreen(group: group)
                        } else {
                            selectedID = group.coordinatorID
                            router.presentedSheet = .groupScreen(group: group)
                        }
                        return
                    }
                }
            }
            
            if components.host?.lowercased() == "services" {
                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
            }
        }
    }
    
    private func configureNuke() {
        let pipeline = ImagePipeline {
            let imageCache = ImageCache.shared
            imageCache.costLimit = 1024 * 1024 * 50 // 50 MB max memory usage
            imageCache.countLimit = 200             // Store up to 200 images
            imageCache.ttl = 60 * 5                 // Keep images in
            $0.imageCache = imageCache
    
            $0.dataCache = try? DataCache(name: "com.clic.imageCache")
        
            // Prefer cached data whenever possible
            $0.dataCachePolicy = .automatic
            
            // Optimize the DataLoader
            let config = URLSessionConfiguration.default
            config.urlCache = nil // disable URLCache, rely on Nuke's DataCache
            config.requestCachePolicy = .reloadIgnoringLocalCacheData // let Nuke handle caching
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 60
            config.waitsForConnectivity = false // fail fast
            
            $0.dataLoader = DataLoader(configuration: config)
            
            // Reduce memory footprint
            $0.makeImageDecoder = { _ in
                return ImageDecoders.Default()
            }
        }
        
        ImagePipeline.shared = pipeline
    }
}


class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
       _ application: UIApplication,
       configurationForConnecting connectingSceneSession: UISceneSession,
       options: UIScene.ConnectionOptions
     ) -> UISceneConfiguration {
         if let shortcutItem = options.shortcutItem {
             if shortcutItem.type == "com.clic.search" {
                 Task { @MainActor in
                     // MARK: Delay for Toolbar
                     try await Task.sleep(for: .milliseconds(200))
                     Router.main.path.removeAll()
                     Router.main.presentedSheet = .search()
                 }
             }
         }

       let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
       sceneConfig.delegateClass = ClicSceneDelegate.self // 👈🏻
       return sceneConfig
     }
    
    override func buildMenu(with builder: UIMenuBuilder) {
        /// Only operate on the main menu bar.
        if builder.system == .main {
            builder.remove(menu: .edit)
            builder.remove(menu: .format)
        }
    }
}

class ClicSceneDelegate: NSObject, UIWindowSceneDelegate {
    var toolbarDelegate = ToolbarDelegate()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
//#if targetEnvironment(macCatalyst)
//        if let titlebar = windowScene.titlebar {
////            let toolbar = NSToolbar(identifier: "main")
////            toolbar.delegate = toolbarDelegate
////            toolbar.displayMode = .iconAndLabel
////            
//            titlebar.titleVisibility = .hidden
//            titlebar.toolbar = nil
////            titlebar.toolbarStyle = .unifiedCompact
////            titlebar.toolbar = toolbar
//        }
//#endif
        
#if targetEnvironment(macCatalyst)
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil // optional, remove toolbar if it hides the title
        }
#endif
    }
    
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {

        if shortcutItem.type == "com.clic.search" {
            Task { @MainActor in
                // MARK: Delay for Toolbar
                try await Task.sleep(for: .milliseconds(200))
                Router.main.path.removeAll()
                Router.main.presentedSheet = .search()
            }
        }
    }
}

final class ToolbarDelegate: NSObject {
    @objc func prefs(_ sender:Any) {
        Task { @MainActor in
            Router.main.presentedSheet = .settings()
        }
    }

    @objc func search(_ sender:Any) {
        Task { @MainActor in
            Router.main.inspectorSheet = .search()
        }
    }
    
    @objc func sorting(_ sender:Any) {
        Task { @MainActor in
            print("HERE")
        }
    }
    
}

#if targetEnvironment(macCatalyst)
extension NSToolbarItem.Identifier {
    static let preferences = NSToolbarItem.Identifier("com.clic.preferences")
    static let sorting = NSToolbarItem.Identifier("com.clic.sorting")
//    static let newFolder = NSToolbarItem.Identifier("com.highcaffeinecontent.catalystexample.newfolder")
//    static let search = NSToolbarItem.Identifier("com.clic.search")
}


extension ToolbarDelegate: NSToolbarDelegate {

    func toolbarIdentifiers() -> [NSToolbarItem.Identifier] {
        return [.sorting, .flexibleSpace, .preferences, .toggleSidebar, .primarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarIdentifiers()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarIdentifiers()
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .preferences {
            let barItem = UIBarButtonItem(image: UIImage(systemName: "switch.2"), style: .plain, target: self, action: #selector(prefs(_:)))
            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
            item.accessibilityLabel = NSLocalizedString("Preferences", comment: "")
            item.toolTip = NSLocalizedString("Preferences", comment: "")
            return item
        }
//        else if itemIdentifier == .search {
//            let barItem = UIBarButtonItem(image: UIImage(systemName: "sparkle.magnifyingglass"), style: .plain, target: self, action: #selector(search))
//            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
//            item.accessibilityLabel = NSLocalizedString("Search", comment: "")
//            item.toolTip = NSLocalizedString("Search", comment: "")
//            return item
//        }
//        else if itemIdentifier == .newFolder {
//            let barItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: nil)
//            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
//            item.accessibilityLabel = NSLocalizedString("TOOLBAR_NEW_FOLDER_BUTTON", comment: "")
//            item.toolTip = NSLocalizedString("TOOLBAR_NEW_FOLDER_BUTTON", comment: "")
//
//            return item
//        }
//        else if itemIdentifier == .search {
//
//            if let searchItem = CATAppDelegate.appKitController?.searchToolbarItem(sceneIdentifier:scene?.session.persistentIdentifier ?? UUID().uuidString, itemIdentifier: itemIdentifier, target: self, selector: #selector(search(_:))) {
//                return searchItem
//            }
////            else {
//                return NSToolbarItem(itemIdentifier: itemIdentifier)
////            }
//        }
//        else {
//            return NSToolbarItem(itemIdentifier: itemIdentifier)
//        }
        
        if itemIdentifier == .sorting {
            let barItem = UIBarButtonItem(image: UIImage(systemName: "switch.2"), style: .plain, target: self, action: #selector(prefs(_:)))
            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
            item.accessibilityLabel = NSLocalizedString("Preferences", comment: "")
            item.toolTip = NSLocalizedString("Preferences", comment: "")
            return item
        }
        return NSToolbarItem(itemIdentifier: itemIdentifier)
    }

}
#endif
