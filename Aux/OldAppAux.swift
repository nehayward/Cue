//import Analytics
//import Defaults
//import Nuke
//import CloudStorage
//import VibesDS
//import RevenueCat
//import RevenueCatUI
//import SonosKit
//import SubscriptionKit
//import MusicKit
//import MusicSearchKit
//import StoreKit
//import SwiftUI
//import TipKit
//import CoreSpotlight
//#if canImport(WidgetKit)
//import WidgetKit
//#endif
//
//@main
//struct AppAux: App {
//    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
//
//    @Environment(\.openWindow) var openWindow
//    @Environment(\.scenePhase) var scenePhase
//    @Environment(\.liveActivityManager) var liveActivityManager
//
//    @State private var router: Router = Router.main
//    @State private var subscriptionService = SubscriptionService.shared
//    @State private var alertService = AlertService.shared
//    @State private var musicSearchService = MusicSearchService.shared
//    @State private var sonosService = SonosService.shared
//
//    private var audioPlaybackService = AudioPlaybackService.shared
//    private var playlistContainer = PlaylistContainer.shared
//    private var playHistoryService = PlayHistoryService.shared
//    private var miniPlayerManager = MiniPlayerManger.shared
//    private var plexRatingCache = PlexRatingCache.shared
//
//    @CloudStorage(CloudKeys.hasSubscription) private var activeSubscription: Bool = false
//    @CloudStorage(CloudKeys.scenes) var scenes: [SonosScene] = []
//    
//    @AppStorage(GroupStorageKeys.hasOnboarded, store: GroupStorageKeys.storage) private var hasOnboarded: Bool = false
//    @AppStorage("ClicMiniEnabled") private var isMenuBarAppEnabled: Bool = true
//    @AppStorage(AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
//    @AppStorage(AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false
//    @AppStorage(AppStorageKeys.showArtworkOnly) private var showArtworkOnly: Bool = false
//    @AppStorage(AppStorageKeys.queueInspectorVisible) private var queueInspectorVisible: Bool = false
//    @AppStorage(AppStorageKeys.savedGroupID) private var savedGroupID: String?
//
//    @State private var previousCount: Int = 0
//    
//#if targetEnvironment(macCatalyst)
//    private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared
//
//    /// Composite key driving `.task(id:)` for the dock menu. Reading these
//    /// properties during body eval registers SwiftUI observation, so any
//    /// change re-fires the refresh task.
//    private var dockRefreshKey: DockMenuCoordinator.RefreshKey {
//        let group = router.selectedID.flatMap { id in sonosService.sorted.first(where: { $0.coordinatorID == id }) }
//        return .init(
//            selectedGroupID: router.selectedID,
//            trackUnique: group?.coordinatorRoom.track.unique,
//            isPlaying: group?.coordinatorRoom.isPlaying ?? false,
//            availableGroupIDs: sonosService.sorted.map { $0.coordinatorID }
//        )
//    }
//#endif
//    
//    var body: some Scene {
//        WindowGroup {
//            NavigationSplitView {
//                SpeakerListScreen()
//                    .navigationSplitViewColumnWidth(min: 320, ideal: 340, max: 400)
//            } detail: {
//                ContainerLargePlayerView()
//            }
//            // Inspector first, sheets outside it: modifiers apply inside-out,
//            // and a `.sheet` hosted *inside* `.inspector` gets torn down when
//            // the inspector restructures (column ↔ sheet on iPad size-class
//            // changes, Catalyst window resizes) — dismissing the presented
//            // sheet out from under the user.
//            .withInspector(inspectorDestination: $router.inspectorSheet)
//            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
//            .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
//            .visionOrnament(router: router)
//            .withAlert()
//            .environment(router)
//            .environment(sonosService)
//            .environment(subscriptionService)
//            .environment(alertService)
//            .environment(musicSearchService)
//            .environment(audioPlaybackService)
//            .environment(playlistContainer)
//            .environment(playHistoryService)
//            .environment(miniPlayerManager)
//            .environment(plexRatingCache)
//            .onOpenURL(perform: handle)
//            .onAppear {
//                guard !AppBootstrapper.shared.didLaunch else { return }
//                AppBootstrapper.shared.didLaunch = true
//                AppBootstrapper.shared.bootstrap()
//
//#if os(iOS) && !targetEnvironment(macCatalyst)
//                // One call for the lifetime of the process: the service watches
//                // the model itself from here on. Deliberately not a view
//                // modifier — SwiftUI stops evaluating bodies in the background,
//                // which is exactly when the Lock Screen card matters.
//                NowPlayingSessionService.shared.activate()
//#endif
//
//                // Wire callbacks before the onboarding gate so events fired
//                // during onboarding (Sonos discovery forming the first group,
//                // a paywall-step purchase) don't fall on the floor.
//                SonosService.shared.groupsChanged = { groups in
//                    guard subscriptionService.subscription.isActive else { return }
//                    liveActivityManager.createActivity(shouldLoad: false)
//                }
//
//                SubscriptionService.shared.subscriptionUpdated = { subscription in
//                    activeSubscription = subscription.isActive
//#if canImport(WidgetKit)
//                    if #available(visionOS 26.0, *) {
//                        WidgetCenter.shared.reloadAllTimelines()
//                    }
//#endif
//                }
//                
//                Task.detached(priority: .utility) {
//                    await LatestReleaseFetcher.refresh()
//                }
//
//                if !hasOnboarded || OnboardingDebug.forceShow {
//                    router.presentedFullScreenCover = .onboard
//                    return
//                }
//
//                Task { @MainActor in
//                    try? await SubscriptionService.shared.checkSubscription()
//                }
//
//#if targetEnvironment(macCatalyst)
//                if isMenuBarAppEnabled {
//                    Task {
//                        try? await Task.sleep(for: .seconds(2))
//                        do {
//                            try await menuAppLaunchAtLoginManager.bridge?.openClicMiniApp()
//                        } catch {
//                            print("Failed to launch ClicMini: \(error.localizedDescription)")
//                        }
//                    }
//                }
//                if let bridge = menuAppLaunchAtLoginManager.bridge {
//                    DockMenuCoordinator.shared.install(
//                        bridge: bridge,
//                        router: router,
//                        sonosService: sonosService
//                    )
//                }
//#endif
//                // Try and restore selected groupID
//                if let savedGroupID = savedGroupID {
//                    Task {
//                        let startTime = Date.now
//                        while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 5 {
//                            try? await Task.sleep(for: .milliseconds(100))
//                        }
//
//                        if sonosService.sorted.contains(where: { $0.coordinatorID == savedGroupID }) {
//                            router.selectedID = savedGroupID
//                        }
//                    }
//                }
//
//                // iPad/Mac: Auto-select first group and restore queue state
//                if UIDevice.current.userInterfaceIdiom != .phone {
//                    Task {
//                        let startTime = Date.now
//                        while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 5 {
//                          try? await Task.sleep(for: .milliseconds(100))
//                        }
//                        try? await Task.sleep(for: .milliseconds(400))
//
//                        // Auto-select first group if none selected (iPad initial launch)
//                        if router.selectedID == nil {
//                            sonosService.selectedGroup = sonosService.sorted.first
//                            router.selectedID = sonosService.sorted.first?.coordinatorID
//                        }
//
//                        // Restore queue inspector if it was open
//                        if queueInspectorVisible {
//                            if let savedGroupID = savedGroupID,
//                               let group = sonosService.sorted.first(where: { $0.coordinatorID == savedGroupID }) {
//
//                                router.inspectorSheet = .queue(group: group)
//                            } else if let selectedID = router.selectedID,
//                                      let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) {
//                                // Fall back to currently selected group
//                                router.inspectorSheet = .queue(group: group)
//                            } else if let firstGroup = sonosService.sorted.first {
//                                // Fall back to first available group
//                                router.inspectorSheet = .queue(group: firstGroup)
//                            }
//                        }
//                    }
//                }
//
//                Task {
//                    ClicAppShortcutProvider.updateAppShortcutParameters()
//                }
//            }
//#if targetEnvironment(macCatalyst)
//            .frame(minWidth: 800, minHeight: 500)
//#endif
//            .fontDesign(.rounded)
//            .onContinueUserActivity(CSSearchableItemActionType) { activity in
//                guard let userInfo = activity.userInfo, let itemIdentifier = userInfo[CSSearchableItemActivityIdentifier] as? String else {
//                    return
//                }
//                if itemIdentifier.starts(with: "SonosDeviceEntity/") {
//                    let deviceID = itemIdentifier.replacingOccurrences(of: "SonosDeviceEntity/", with: "")
//                    
//                    Task {
//                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: deviceID) else { return }
//                        router.selectedID = group.coordinatorID
//                    }
//                }
//            }
//            .preferredColorScheme(colorScheme.scheme)
//#if targetEnvironment(macCatalyst)
//            // Single source of truth for dock-menu refresh. The RefreshKey
//            // reads selectedID, the current group's track + isPlaying, and
//            // the list of available groups — so any change re-fires the task,
//            // and SwiftUI auto-cancels any in-flight refresh from the
//            // previous key. `.task` is a View modifier, so it must live
//            // inside WindowGroup, not on the Scene.
//            .task(id: dockRefreshKey) {
//                await DockMenuCoordinator.shared.refresh()
//            }
//#endif
//        }
//        .windowResizability(.contentMinSize)
//        .onChange(of: scenePhase) {
//            handleScenePhase(scenePhase)
//        }
//        .onChange(of: subscriptionService.subscription, initial: true) { oldValue, newValue in
//            activeSubscription =  newValue.isActive
//        }
//        .onChange(of: router.selectedID) {
//            // No inspector re-targeting here: InspectorContentView (and the
//            // visionOS ornament) resolve the selected group live from
//            // router.selectedID, so the destination enum's captured group is
//            // only a fallback.
//            savedGroupID = router.selectedID
//        }
//        .onChange(of: sonosService.groups) {
//            if sonosService.rooms.count == previousCount {
//                return
//            }
//
//            Analytics.shared.track(.numberOfDevices, with: ["Device Count" : sonosService.rooms.count,
//                                                            "Subscriber": subscriptionService.subscription.isActive])
//            previousCount = sonosService.rooms.count
//        }
//        .onChange(of: sonosService.sortedRooms) {
//            if #available(iOS 18.0, *) {
//                Task {
//                    try? await CSSearchableIndex.default().deleteAllSearchableItems()
//                    try? await CSSearchableIndex.default().indexAppEntities(
//                        sonosService.sortedRooms.map { SonosDeviceEntity(id: $0.id, ip: $0.ip, name: $0.name)}
//                    )
//                }
//            }
//        }
//        .onChange(of: router.inspectorSheet) { oldValue, newValue in
//            if UIDevice.current.userInterfaceIdiom != .phone  {
//                queueInspectorVisible = (newValue?.id == "queue")
//            }
//        }
//        .onChange(of: sonosService.isCellular) { oldValue, isCellular in
//            if isCellular {
//                router.selectedID = nil
//                router.inspectorSheet = nil
//                sonosService.clearDevices()
//                alertService.showAlert(with: "On Cellular", imageName: "wifi.slash")
//            } else if oldValue {
//                // Coming back from cellular to WiFi - restart discovery
//                sonosService.monitor()
//            }
//        }
//        .commands {
//            SidebarCommands()
//            CommandGroup(replacing: .appSettings) {
//                Button {
//                    Router.main.presentedSheet = .settings()
//                } label: {
//                    Label("Settings", systemImage: "gear")
//                }
//                .keyboardShortcut(",", modifiers: .command)
//            }
//            CommandGroup(after: .sidebar) {
//                Divider()
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
//                        router.toggleInspector(.search(group: sonosService.sorted[group]))
//                    }
//                } label: {
//                    Label("\(router.inspectorSheet?.id ?? "" == "search" ? "Hide" : "Show") Search", systemImage: "magnifyingglass")
//                }
//                .keyboardShortcut("s", modifiers: [])
//
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
//                        router.toggleInspector(.browse(group: sonosService.sorted[group]))
//                    }
//                } label: {
//                    Label("\(router.inspectorSheet?.id ?? "" == "browse" ? "Hide" : "Show") Browse", image: "home.fill")
//                }
//                .keyboardShortcut("b", modifiers: [])
//
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
//                        router.toggleInspector(.queue(group: sonosService.sorted[group]))
//                    }
//                } label: {
//                    Label("\(router.inspectorSheet?.id ?? "" == "queue" ? "Hide" : "Show") Queue", systemImage: "list.dash")
//                }
//                .keyboardShortcut("q", modifiers: [])
//                
//                Button {
//                    router.sheet(to: .settings(destination: .alarms))
//                } label: {
//                    Label("Show Alarms", systemImage: "alarm.fill")
//                }
//                .keyboardShortcut("a", modifiers: [.shift, .command])
//                
//                Toggle(isOn: $showArtworkOnly) {
//                    Label("Album Cover Only", systemImage: "photo")
//                    Text("Hide titles and controls.")
//                }
//                .keyboardShortcut("f", modifiers: [.shift, .command])
//            }
//            CommandMenu("Playback") {
//                PlaybackTransportControls(router: router, sonosService: sonosService)
//
//                Button {
//                    Task {
//                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                            HapticManager.shared.fireHaptic(.selection)
//                            let newPosition = group.coordinatorRoom.playbackPosition + 15000
//                            await sonosService.seek(to: newPosition, on: group)
//                        }
//                    }
//                } label: {
//                    Label("Seek Forward", systemImage: "goforward")
//                }
//                .keyboardShortcut(.rightArrow, modifiers: .option)
//                .disabled(router.selectedID == nil)
//
//                Button {
//                    Task {
//                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                            HapticManager.shared.fireHaptic(.selection)
//                            let newPosition = max(0, group.coordinatorRoom.playbackPosition - 15000)
//                            await sonosService.seek(to: newPosition, on: group)
//                        }
//                    }
//                } label: {
//                    Label("Seek Backward", systemImage: "gobackward")
//                }
//                .keyboardShortcut(.leftArrow, modifiers: .option)
//                .disabled(router.selectedID == nil)
//
//                Divider()
//
//                Button {
//                    Task {
//                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                            var currentPlayMode = group.playMode
//                            if currentPlayMode.contains(.shuffle) {
//                                currentPlayMode.remove(.shuffle)
//                            } else {
//                                currentPlayMode.insert(.shuffle)
//                            }
//                            group.playMode = currentPlayMode
//                            await sonosService.setPlayMode(group.ip, mode: currentPlayMode)
//                        }
//                    }
//                } label: {
//                    Label("Shuffle", systemImage: "shuffle")
//                }
//                .keyboardShortcut("s")
//                .disabled(router.selectedID == nil)
//
//                Button {
//                    Task {
//                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                            var currentPlayMode = group.playMode
//                            if !currentPlayMode.isRepeatEnabled {
//                                currentPlayMode.insert(.repeatAll)
//                            } else if currentPlayMode.isRepeatAllEnabled {
//                                currentPlayMode.remove(.repeatAll)
//                                currentPlayMode.insert(.repeatOne)
//                            } else {
//                                currentPlayMode.remove(.repeatOne)
//                                currentPlayMode.remove(.repeatAll)
//                            }
//                            group.playMode = currentPlayMode
//                            await sonosService.setPlayMode(group.ip, mode: currentPlayMode)
//                        }
//                    }
//                } label: {
//                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                        Label("Repeat", systemImage: group.playMode.contains(.repeatOne) ? "repeat.1" : "repeat")
//                    } else {
//                        Label("Repeat", systemImage: "repeat")
//                    }
//                }
//                .keyboardShortcut("r")
//                .disabled(router.selectedID == nil)
//
//                Divider()
//
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                        router.sheet(to: .mediaDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
//                    }
//                } label: {
//                    Label("Open Album", systemImage: "smallcircle.circle.fill")
//                }
//                .keyboardShortcut("i", modifiers: [.shift, .command])
//                .disabled(router.selectedID == nil)
//
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                        router.sheet(to: .artistDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
//                    }
//                } label: {
//                    Label("Open Artist", systemImage: "music.mic")
//                }
//                .keyboardShortcut("i", modifiers: [.command])
//                .disabled(router.selectedID == nil)
//            }
////            CommandGroup(after: .windowArrangement) {
////                Button {
////                    openWindow(id: "mini")
////                } label: {
////                    Text("Mini Player")
////                }
////                .keyboardShortcut("0")
////            }
//        }
////        Window(id: "mini") {
////            VStack {
////                MiniPlayerView()
////                    .environment(SelectedGroupService(group: sonosService.selectedGroup))
////                    .withEnvironments()
////            }
////        }
////        .windowResizability(.contentSize)
//    }
//
//    @MainActor
//    private func handleScenePhase(_ scenePhase: ScenePhase) {
//        switch scenePhase {
//        case .active:
//            // Printed like the other two: without it a scene trace reads
//            // `Inactive … Monitoring!` with no way to tell whether the app came
//            // back or something else restarted the pulse. That ambiguity is what
//            // hid `stopMonitoringOffScreen`'s bug.
//            print("Active")
//            // Don't poke the network (which triggers the Local Network
//            // permission prompt) until onboarding has surfaced the explanation
//            // screen and the user has tapped Continue. WelcomeScreen kicks off
//            // `monitor()` on dismiss.
//            guard hasOnboarded, !OnboardingDebug.forceShow else { return }
//            // The network may have changed while backgrounded (e.g. home →
//            // friend's house). Re-race known IPs + discovery on the next poll
//            // instead of blocking on a now-stale cached IP. Cheap: an unchanged
//            // network still wins in ms, and the flag re-verifies after one load.
//            sonosService.invalidateVerifiedConnection()
//            // Re-opened before `monitor()`, and before any view `.task` that
//            // fires as the app comes back can call it — this runs first on the
//            // activation.
//            sonosService.allowsMonitoring = true
//            sonosService.monitor()
//#if targetEnvironment(macCatalyst)
//            // Window is open — live monitoring + `.task(id:)` keep the dock
//            // menu fresh, so the background poll isn't needed.
//            DockMenuCoordinator.shared.stopBackgroundRefresh()
//#endif
//            Task {
//                let startTime = Date.now
//                while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 10 {
//                    try? await Task.sleep(for: .milliseconds(100))
//                }
//                guard !sonosService.sorted.isEmpty else { return }
//                sonosService.onServerListening()
//            }
//            
//            if speedLaunchNowPlaying {
//                Task {
//                    try? await Task.sleep(for: .milliseconds(200))
//                    if sonosService.groups.isEmpty {
//                        try? await sonosService.updateGroups()
//                    }
//                    handle(URL(string: "clic://playing")!)
//                }
//            }
//            
//            if !subscriptionService.subscription.isActive {
//                return
//            }
//            
//            Task {
//                for group in sonosService.groups {
//                    if !group.coordinatorRoom.isPlaying {
//                        await liveActivityManager.stop(id: group.coordinatorRoom.id)
//                    }
//                }
//            }
//
//            Task {
//                try? await subscriptionService.checkSubscription()
//            }
//
//            Task {
//                try? await Task.sleep(for: .seconds(1))
//                ReviewCoordinator.shared.requestReview()
//            }
//        case .inactive:
//            print("Inactive")
//#if canImport(WidgetKit)
//            if #available(visionOS 26.0, *) {
//                WidgetCenter.shared.reloadAllTimelines()
//            }
//#endif
//            Task {
//                await liveActivityManager.refresh()
//            }
//            stopMonitoringOffScreen(scenePhase)
//        case .background:
//            print("Background")
//            stopMonitoringOffScreen(scenePhase)
//#if targetEnvironment(macCatalyst)
//            // Monitoring is now cancelled, so the cached model freezes. Poll
//            // the selected group on a slow cadence to keep the dock menu
//            // current (it's built synchronously and can't fetch on open).
//            DockMenuCoordinator.shared.startBackgroundRefresh()
//#endif
//        @unknown default:
//            break
//        }
//    }
//
//    /// Stops the SOAP pulse and the volume watcher, which exist to feed on-screen
//    /// UI and are the app's most expensive recurring work — `load()` plus a
//    /// per-group sweep every 500–800 ms.
//    ///
//    /// Called for `.inactive` as well as `.background`, because **the phone
//    /// locking with Clic frontmost does not reliably reach `.background`**. With
//    /// the Lock Screen card's audio session held the scene often parks at
//    /// `.inactive` instead, and keying the teardown on `.background` alone left
//    /// both loops polling with the screen off — sometimes for the whole time the
//    /// phone was locked. The scene trace behind that bug reads
//    /// `Inactive, Inactive, Inactive` with no `Background` at all.
//    ///
//    /// A transient `.inactive` — a notification banner, a Control Centre pull,
//    /// the app switcher — costs one `monitor()` restart on the way back, the
//    /// same as any foreground return. That is cheap, and much cheaper than the
//    /// case this exists to stop.
//    ///
//    /// Not on iPad: there, `.inactive` is also what a *visible* window in Split
//    /// View or Stage Manager reports when it merely isn't the focused one, and
//    /// freezing a window the user can see would be a real regression. iPad keeps
//    /// the old `.background`-only behaviour until there's a signal that
//    /// separates "not focused" from "not on screen".
//    ///
//    /// Guarded on onboarding for the same reason `.active` is: the Local Network
//    /// permission prompt makes the scene `.inactive` while it's up, and `.active`
//    /// deliberately doesn't restart monitoring before onboarding is done — so
//    /// tearing down here would stop discovery with nothing to start it again.
//    @MainActor
//    private func stopMonitoringOffScreen(_ phase: ScenePhase) {
//        guard hasOnboarded, !OnboardingDebug.forceShow else { return }
//        if phase == .inactive, UIDevice.current.userInterfaceIdiom == .pad { return }
//
//        // Shut the gate before cancelling, not after: cancelling only stops the
//        // loops that are running, and `monitor()` is called from a dozen places
//        // — a Search button, several view `.task`s, the cellular-recovery
//        // handler — any of which would restart them behind a locked screen.
//        // `SonosService.allowsMonitoring` is what makes this a guarantee rather
//        // than a race.
//        sonosService.allowsMonitoring = false
//        sonosService.sonosPulse.cancel()
//        sonosService.watcher.cancel()
//    }
//
//    @MainActor
//    private func handle(_ url: URL) {
//        Task {
//            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
//            
//            if sonosService.groups.isEmpty {
//                try? await sonosService.updateGroups()
//            }
//            
//            if components.host?.lowercased() == "playing" {
//                guard let group = await sonosService.firstPlayingGroup() else {
//                    return
//                }
//                router.selectedID = group.coordinatorID
//                return
//            }
//            
//            if components.host?.lowercased() == "alarms" {
//                router.presentedSheet = .settings(destination: .alarms)
//                return
//            }
//            
//            if components.host?.lowercased() == "subscribe" {
//                router.presentedFullScreenCover = .paywall
//                return
//            }
//            
//            if components.host?.lowercased() == "search", url.pathComponents.contains("favorites") {
//                // Navigate to favorite search
//                router.path.removeAll()
//                router.presentedSheet = .favorites
//                return
//            }
//
//            if components.host?.lowercased() == "search", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
//                router.presentedSheet = nil
//                
//
//                guard let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) else {
//                    Task {
//                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
//                            return
//                        }
//                        router.selectedID = group.coordinatorID
//                        if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
//                            router.presentedSheet = .search(group: group)
//                        } else {
//                            router.inspectorSheet = .search(group: group)
//                        }
//                    }
//                    return
//                }
//                router.selectedID = group.coordinatorID
//                if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
//                    router.presentedSheet = .search(group: group)
//                } else {
//                    router.inspectorSheet = .search(group: group)
//                }
//                return
//            }
//
//            if components.host?.lowercased() == "device", let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
//                router.presentedSheet = nil
//
//                guard let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) else {
//                    Task {
//                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
//                            return
//                        }
//                        router.selectedID = group.coordinatorID
//                    }
//                    return
//                }
//                router.selectedID = group.coordinatorID
//            }
//            
//            // MARK: Add Back for queue
////            if let roomName = components.host {
////                guard let groupID = components.queryItems?.first(where: { $0.name == "id" })?.value else { return }
////
////                guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: groupID) else {
////                    return
////                }
////
////                if url.pathComponents.contains("queue") || components.queryItems?.contains(where: { $0.name == "showqueue" }) == true {
////                    router.selectedID = group.coordinatorID
////                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
////                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
////                        router.presentedSheet = .queue(group: sonosService.groups[groupIndex])
////                    } else {
////                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
////                        router.inspectorSheet = .queue(group: sonosService.groups[groupIndex])
////                    }
////                } else if url.pathComponents.contains("search") || components.queryItems?.contains(where: { $0.name == "showsearch" }) == true {
////                    router.selectedID = group.coordinatorID
////                    guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
////                    router.inspectorSheet = .search(group: sonosService.groups[groupIndex])
////                } else if url.pathComponents.contains("browse") || components.queryItems?.contains(where: { $0.name == "showbrowse" }) == true {
////                    router.selectedID = group.coordinatorID
////                    // Show browse
////                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
////                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
////                        router.presentedSheet = .browse(group: sonosService.groups[groupIndex])
////                    } else {
////                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
////                        router.inspectorSheet = .browse(group: sonosService.groups[groupIndex])
////                    }
////                } else {
////                    router.selectedID = group.coordinatorID
////                }
////                return
////            }
//
//            if components.host?.lowercased() == "scene", let name = components.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
//                guard let scene = scenes.first(where: { $0.name == name }) else { return }
//                Task {
//                    if let content = scene.playableContent {
//                        alertService.showAlertContent(with: content, subtitle: "Running \(scene.name)", symbolName: "bolt.fill")
//                    } else {
//                        alertService.showAlert(with: "Running \(scene.name)")
//                    }
//                    try await sonosService.runScene(scene)
//                }
//            }
//
//            if components.host?.lowercased() == "play", let paths = components.string?.split(separator: "/").map(String.init), let url = components.url {
//                if paths.count < 3 {
//                    return
//                }
//                router.sheet(to: .playMedia(url: url))
//            }
//
//            if components.host?.lowercased() == "view", let url = components.url {
//                Task {
//                    guard let content = await sonosService.getContent(from: url) else { return }
//                    if content.content.type == .artist || content.content.type == .libraryArtist {
//                        router.sheet(to: .artistDetail(content: content, group: nil))
//                    } else if content.content.type.isRadio {
//                        // Stations have no detail screen — open the play sheet
//                        // so the user can pick a room.
//                        router.sheet(to: .playMedia(url: url))
//                    } else {
//                        router.sheet(to: .mediaDetail(content: content, group: nil))
//                    }
//                }
//            }
//
//            // Fallback for the share extension: when it can't resolve the
//            // shared link itself, it forwards the original URL via
//            // clic://resolve?url=<encoded>. The main app has full
//            // SonosService/MusicKit access and can resolve it here.
//            if components.host?.lowercased() == "resolve",
//               let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
//               let originalURL = URL(string: raw) {
//                router.sheet(to: .playMedia(url: originalURL))
//            }
//
//            if components.host?.lowercased() == "group", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
//                router.presentedSheet = nil
//                if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
//                    router.selectedID = group.coordinatorID
//                    router.presentedSheet = .groupScreen(group: group)
//                }
//                Task {
//                    try await sonosService.load(useCache: true)
//                    if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
//                        router.selectedID = group.coordinatorID
//                        router.presentedSheet = .groupScreen(group: group)
//                        return
//                    }
//                }
//            }
//            
//            if components.host?.lowercased() == "services" {
//                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
//            }
//        }
//    }
//}
//
//
///// Transport buttons for the "Playback" command menu. Extracted into its own
///// View because inlining all five buttons (each with conditional labels and
///// async closures) pushed the `Commands` builder past the type-checker's
///// reasonable-time limit.
//private struct PlaybackTransportControls: View {
//    let router: Router
//    let sonosService: SonosService
//
//    private var selectedGroup: GroupRoom? {
//        guard let id = router.selectedID else { return nil }
//        return sonosService.sorted.first { $0.coordinatorID == id }
//    }
//
//    var body: some View {
//        ControlGroup(selectedGroup?.nameWithCount ?? "No Group Selected") {
//            Button {
//                Task {
//                    guard let group = selectedGroup else { return }
//                    HapticManager.shared.fireHaptic(.selection)
//                    if group.coordinatorRoom.isPlaying {
//                        await sonosService.pause(ip: group.coordinatorRoom.ip)
//                    } else {
//                        await sonosService.play(ip: group.coordinatorRoom.ip)
//                    }
//                }
//            } label: {
//                let playing = selectedGroup?.coordinatorRoom.isPlaying ?? false
//                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
//            }
//            .keyboardShortcut(.space, modifiers: [])
//
//            Button {
//                Task {
//                    guard let group = selectedGroup else { return }
//                    HapticManager.shared.fireHaptic(.selection)
//                    // Twin of the transport buttons in LargePlayerView: a
//                    // deliberate skip snaps the artwork over rather than
//                    // crossfading it.
//                    router.beginSkipWindow()
//                    await sonosService.previous(ip: group.coordinatorRoom.ip)
//                }
//            } label: {
//                Label("Previous Track", systemImage: "backward.fill")
//            }
//            .keyboardShortcut(.leftArrow)
//            .disabled(router.selectedID == nil)
//
//            Button {
//                Task {
//                    guard let group = selectedGroup else { return }
//                    HapticManager.shared.fireHaptic(.selection)
//                    group.coordinatorRoom.playbackPosition = 0
//                    router.beginSkipWindow()
//                    await sonosService.next(ip: group.coordinatorRoom.ip)
//                }
//            } label: {
//                Label("Next Track", systemImage: "forward.fill")
//            }
//            .keyboardShortcut(.rightArrow)
//            .disabled(router.selectedID == nil)
//
//            Button {
//                Task {
//                    guard let group = selectedGroup else { return }
//                    HapticManager.shared.fireHaptic(.selection)
//                    await sonosService.setRelativeGroupVolume(ip: group.ip, volume: 5)
//                }
//            } label: {
//                Label("Volume Up", systemImage: "speaker.wave.2.fill")
//            }
//            .keyboardShortcut(.upArrow)
//            .disabled(router.selectedID == nil)
//
//            Button {
//                Task {
//                    guard let group = selectedGroup else { return }
//                    HapticManager.shared.fireHaptic(.selection)
//                    await sonosService.setRelativeGroupVolume(ip: group.ip, volume: -5)
//                }
//            } label: {
//                Label("Volume Down", systemImage: "speaker.wave.1.fill")
//            }
//            .keyboardShortcut(.downArrow)
//            .disabled(router.selectedID == nil)
//        }
//    }
//}
//
//class AppDelegate: UIResponder, UIApplicationDelegate {
//    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
//        #if targetEnvironment(macCatalyst)
//        // macOS auto-injects "Start Dictation" and "Emoji & Symbols" into any Edit menu. Opt out so
//        // ours carries only Undo/Redo. (AutoFill is removed via the menu builder.)
//        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
//        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
//        #endif
//        return true
//    }
//
//    func application(
//       _ application: UIApplication,
//       configurationForConnecting connectingSceneSession: UISceneSession,
//       options: UIScene.ConnectionOptions
//     ) -> UISceneConfiguration {
//         if let shortcutItem = options.shortcutItem {
//             if shortcutItem.type == "com.clic.search" {
//                 Task { @MainActor in
//                     // MARK: Delay for Toolbar
//                     try await Task.sleep(for: .milliseconds(200))
//                     Router.main.path.removeAll()
//                     Router.main.presentedSheet = .search()
//                 }
//             }
//         }
//
//       let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
//       sceneConfig.delegateClass = ClicSceneDelegate.self // 👈🏻
//       return sceneConfig
//     }
//    
//    override func buildMenu(with builder: UIMenuBuilder) {
//        /// Only operate on the main menu bar.
//        if builder.system == .main {
//            // Remove the system Edit menu entirely — macOS force-injects AutoFill / Start Dictation /
//            // Emoji & Symbols into any Edit menu. Undo/Redo live in a dedicated Playlist menu instead.
//            builder.remove(menu: .edit)
//            builder.remove(menu: .format)
//            builder.remove(menu: .newScene)
//            builder.remove(menu: .open)
//            builder.remove(menu: .openRecent)
//            builder.remove(menu: .document)
//
//            // Add New Playlist to File menu
//            let newPlaylistCommand = UIKeyCommand(
//                title: "New Playlist",
//                image: UIImage(systemName: "music.note.list"),
//                action: #selector(newPlaylist),
//                input: "n",
//                modifierFlags: .command
//            )
//
//            // Add to Last Playlist command (dynamic title)
//            let addToLastPlaylistAction: UIMenuElement
//
//            if let last = LastPlaylist.current {
//                addToLastPlaylistAction = UIKeyCommand(
//                    title: "Add to \(last.title)",
//                    image: last.service.uiImage ?? UIImage(systemName: "text.badge.plus"),
//                    action: #selector(addToLastPlaylist),
//                    input: "s",
//                    modifierFlags: [.shift, .command]
//                )
//            } else {
//                addToLastPlaylistAction = UIAction(title: "Add to Last Playlist", attributes: .disabled) { _ in }
//            }
//
//            // Add to Playlist submenu with deferred loading
//            let addToPlaylistDeferred = UIDeferredMenuElement.uncached { completion in
//                Task { @MainActor in
//                    let sonosService = SonosService.shared
//                    let alertService = AlertService.shared
//                    let musicSearchService = MusicSearchService.shared
//
//                    // Get current track from selected group
//                    guard let selectedID = Router.main.selectedID,
//                          let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) else {
//                        completion([
//                            UIAction(title: "No Track Playing", attributes: .disabled) { _ in }
//                        ])
//                        return
//                    }
//
//                    let track = group.coordinatorRoom.track.toPlayable
//
//                    // Adds `track` to `playlist`, dispatching to Sonos or the streaming service.
//                    func action(for playlist: PlayableContent) -> UIAction {
//                        UIAction(title: playlist.title, image: playlist.content.service.uiImage) { _ in
//                            Task { @MainActor in
//                                let success: Bool
//                                if playlist.content.service == .library {
//                                    await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: track)
//                                    success = true
//                                } else {
//                                    success = await musicSearchService.addToServicePlaylist(track: track, playlist: playlist)
//                                }
//                                guard success else {
//                                    alertService.showAlert(with: "Couldn’t add to \(playlist.title)", imageName: "exclamationmark.triangle")
//                                    return
//                                }
//                                alertService.showAlertContent(with: track, subtitle: "Added to \(playlist.title)", symbolName: "plus")
//                                LastPlaylist.save(playlist)
//                                alertService.alert.handleTap = {
//                                    Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
//                                }
//                            }
//                        }
//                    }
//
//                    var menuItems: [UIMenuElement] = []
//
//                    // The track's own streaming-service playlists (Apple Music / Spotify / Plex / Deezer).
//                    let service = track.content.service
//                    if [.apple, .spotify, .plex, .deezer].contains(service),
//                       [.track, .libraryTrack].contains(track.content.type) {
//                        let servicePlaylists = await musicSearchService.userPlaylists(for: service)
//                        if !servicePlaylists.isEmpty {
//                            menuItems.append(UIMenu(title: service.title, options: .displayInline, children: servicePlaylists.map(action)))
//                        }
//                    }
//
//                    // Sonos playlists accept any track.
//                    let sonosPlaylists = await sonosService.sonosPlaylists()
//                    if !sonosPlaylists.isEmpty {
//                        menuItems.append(UIMenu(title: "Sonos", options: .displayInline, children: sonosPlaylists.map(action)))
//                    }
//
//                    if menuItems.isEmpty {
//                        menuItems = [UIAction(title: "No Playlists", attributes: .disabled) { _ in }]
//                    }
//
//                    completion(menuItems)
//                }
//            }
//
//            let addToPlaylistMenu = UIMenu(
//                title: "Add to Playlist",
//                image: UIImage(systemName: "text.badge.plus"),
//                children: [addToPlaylistDeferred]
//            )
//
//            // A dedicated Playlist menu gathers every playlist action plus Undo/Redo, on all
//            // platforms — so ⌘Z works with a hardware keyboard on iPad/iPhone too, not just Catalyst.
//            // (We don't reuse the Edit menu: macOS injects AutoFill/Dictation/Emoji into it.)
//            // Undo/Redo route through the responder chain (playlistUndo/playlistRedo) and enable via
//            // canPerformAction.
//            let undoCommand = UIKeyCommand(title: "Undo", action: #selector(playlistUndo), input: "z", modifierFlags: .command)
//            let redoCommand = UIKeyCommand(title: "Redo", action: #selector(playlistRedo), input: "z", modifierFlags: [.command, .shift])
//            let playlistMenu = UIMenu(title: "Playlist", identifier: UIMenu.Identifier("com.clic.playlistMenu"), children: [
//                UIMenu(title: "", options: .displayInline, children: [newPlaylistCommand, addToLastPlaylistAction, addToPlaylistMenu]),
//                UIMenu(title: "", options: .displayInline, children: [undoCommand, redoCommand])
//            ])
//            builder.insertSibling(playlistMenu, afterMenu: .file)
//        }
//    }
//
//    /// Drives the foreground playlist editor's undo, routed from the Playlist menu / ⌘Z.
//    @objc func playlistUndo() {
//        PlaylistUndoMenuBridge.shared.editor?.undo()
//    }
//
//    /// Drives the foreground playlist editor's redo, routed from the Playlist menu / ⌘⇧Z.
//    @objc func playlistRedo() {
//        PlaylistUndoMenuBridge.shared.editor?.redo()
//    }
//
//    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
//        switch action {
//        case #selector(playlistUndo):
//            return PlaylistUndoMenuBridge.shared.editor?.canUndo ?? false
//        case #selector(playlistRedo):
//            return PlaylistUndoMenuBridge.shared.editor?.canRedo ?? false
//        default:
//            return super.canPerformAction(action, withSender: sender)
//        }
//    }
//
//    @objc func newPlaylist() {
//        Router.main.presentedSheet = .newPlaylist()
//    }
//
//    @objc func addToLastPlaylist() {
//        let sonosService = SonosService.shared
//        let alertService = AlertService.shared
//
//        guard let last = LastPlaylist.current else {
//            alertService.showAlert(with: "No Recent Playlist", imageName: "exclamationmark.triangle")
//            return
//        }
//
//        guard let selectedID = Router.main.selectedID,
//              let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) else {
//            alertService.showAlert(with: "No Group Selected", imageName: "exclamationmark.triangle")
//            return
//        }
//
//        let currentTrack = group.coordinatorRoom.track.toPlayable
//
//        Task { @MainActor in
//            // Attempt the add and report the real result — the now-playing track's reported service
//            // isn't reliable enough to pre-gate on (a Spotify track can surface as a Sonos item).
//            guard await last.add(currentTrack) else {
//                alertService.showAlert(with: "Couldn’t add to \(last.title)", imageName: "exclamationmark.triangle")
//                return
//            }
//            alertService.showAlertContent(with: currentTrack, subtitle: "Added to \(last.title)", symbolName: "plus")
//
//            // Let tapping the toast open the playlist. Sonos resolves the real playlist for artwork;
//            // streaming opens from a lightweight stub (the detail view loads it by id).
//            let target: PlayableContent?
//            if last.service == .library {
//                target = await sonosService.sonosPlaylists().first(where: { $0.id == last.id })
//            } else {
//                target = last.playableContent
//            }
//            if let target {
//                alertService.alert.handleTap = {
//                    Router.main.presentedSheet = .mediaDetail(content: target, group: nil)
//                }
//            }
//        }
//    }
//}
//
//class ClicSceneDelegate: NSObject, UIWindowSceneDelegate {
//    var toolbarDelegate = ToolbarDelegate()
//    #if targetEnvironment(macCatalyst)
//    private var windowSizeObserver: WindowSizeObserver?
//    #endif
//    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
//        guard let windowScene = (scene as? UIWindowScene) else { return }
//        
//#if targetEnvironment(macCatalyst)
//        if let titlebar = windowScene.titlebar {
//            titlebar.titleVisibility = .hidden
//            titlebar.toolbar = nil
//        }
//        
//        // Set size restrictions
//        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 500)
//        windowScene.sizeRestrictions?.maximumSize = CGSize(width: 2000, height: 1500)
//        
//        // Restore saved window frame
//        if let savedFrame = WindowFrameStore.savedFrame {
//            let geometry = UIWindowScene.GeometryPreferences.Mac(systemFrame: savedFrame)
//            windowScene.requestGeometryUpdate(geometry)
//        }
//        
//        // Start observing window size changes
//        windowSizeObserver = WindowSizeObserver(windowScene: windowScene)
//#endif
//    }
//    
//    func sceneDidDisconnect(_ scene: UIScene) {
//#if targetEnvironment(macCatalyst)
//        windowSizeObserver = nil
//#endif
//    }
//    
//    func windowScene(_ windowScene: UIWindowScene,
//                     performActionFor shortcutItem: UIApplicationShortcutItem,
//                     completionHandler: @escaping (Bool) -> Void) {
//
//        if shortcutItem.type == "com.clic.search" {
//            Task { @MainActor in
//                // MARK: Delay for Toolbar
//                try await Task.sleep(for: .milliseconds(200))
//                Router.main.path.removeAll()
//                Router.main.presentedSheet = .search()
//            }
//        }
//    }
//}
//
//final class ToolbarDelegate: NSObject {
//    @objc func prefs(_ sender:Any) {
//        Task { @MainActor in
//            Router.main.presentedSheet = .settings()
//        }
//    }
//
//    @objc func search(_ sender:Any) {
//        Task { @MainActor in
//            Router.main.inspectorSheet = .search()
//        }
//    }
//    
//    @objc func sorting(_ sender:Any) {
//        Task { @MainActor in
//            print("HERE")
//        }
//    }
//    
//}
//
//#if targetEnvironment(macCatalyst)
//extension NSToolbarItem.Identifier {
//    static let preferences = NSToolbarItem.Identifier("com.clic.preferences")
//    static let sorting = NSToolbarItem.Identifier("com.clic.sorting")
////    static let newFolder = NSToolbarItem.Identifier("com.highcaffeinecontent.catalystexample.newfolder")
////    static let search = NSToolbarItem.Identifier("com.clic.search")
//}
//
//
//extension ToolbarDelegate: NSToolbarDelegate {
//
//    func toolbarIdentifiers() -> [NSToolbarItem.Identifier] {
//        return [.sorting, .flexibleSpace, .preferences, .toggleSidebar, .primarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace]
//    }
//
//    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
//        return toolbarIdentifiers()
//    }
//
//    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
//        return toolbarIdentifiers()
//    }
//
//    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
//        if itemIdentifier == .preferences {
//            let barItem = UIBarButtonItem(image: UIImage(systemName: "switch.2"), style: .plain, target: self, action: #selector(prefs(_:)))
//            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
//            item.accessibilityLabel = NSLocalizedString("Preferences", comment: "")
//            item.toolTip = NSLocalizedString("Preferences", comment: "")
//            return item
//        }
////        else if itemIdentifier == .search {
////            let barItem = UIBarButtonItem(image: UIImage(systemName: "sparkle.magnifyingglass"), style: .plain, target: self, action: #selector(search))
////            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
////            item.accessibilityLabel = NSLocalizedString("Search", comment: "")
////            item.toolTip = NSLocalizedString("Search", comment: "")
////            return item
////        }
////        else if itemIdentifier == .newFolder {
////            let barItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: nil)
////            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
////            item.accessibilityLabel = NSLocalizedString("TOOLBAR_NEW_FOLDER_BUTTON", comment: "")
////            item.toolTip = NSLocalizedString("TOOLBAR_NEW_FOLDER_BUTTON", comment: "")
////
////            return item
////        }
////        else if itemIdentifier == .search {
////
////            if let searchItem = CATAppDelegate.appKitController?.searchToolbarItem(sceneIdentifier:scene?.session.persistentIdentifier ?? UUID().uuidString, itemIdentifier: itemIdentifier, target: self, selector: #selector(search(_:))) {
////                return searchItem
////            }
//////            else {
////                return NSToolbarItem(itemIdentifier: itemIdentifier)
//////            }
////        }
////        else {
////            return NSToolbarItem(itemIdentifier: itemIdentifier)
////        }
//        
//        if itemIdentifier == .sorting {
//            let barItem = UIBarButtonItem(image: UIImage(systemName: "switch.2"), style: .plain, target: self, action: #selector(prefs(_:)))
//            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
//            item.accessibilityLabel = NSLocalizedString("Preferences", comment: "")
//            item.toolTip = NSLocalizedString("Preferences", comment: "")
//            return item
//        }
//        return NSToolbarItem(itemIdentifier: itemIdentifier)
//    }
//
//}
//#endif
