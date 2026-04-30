import Analytics
import Defaults
import Nuke
import CloudStorage
import VibesDS
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

    @Environment(\.openWindow) var openWindow
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.liveActivityManager) var liveActivityManager

    @State private var router: Router = Router.main
    @State private var subscriptionService = SubscriptionService.shared
    @State private var alertService = AlertService.shared
    @State private var musicSearchService = MusicSearchService.shared
    @State private var sonosService = SonosService.shared

    private var audioPlaybackService = AudioPlaybackService.shared
    private var playlistContainer = PlaylistContainer.shared
    private var playHistoryService = PlayHistoryService.shared
    private var miniPlayerManager = MiniPlayerManger.shared

    @CloudStorage(CloudKeys.hasSubscription) private var activeSubscription: Bool = false
    @CloudStorage(CloudKeys.scenes) var scenes: [SonosScene] = []
    
    @AppStorage(GroupStorageKeys.hasOnboarded, store: GroupStorageKeys.storage) private var hasOnboarded: Bool = false
    @AppStorage("ClicMiniEnabled") private var isMenuBarAppEnabled: Bool = true
    @AppStorage(AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false
    @AppStorage(AppStorageKeys.showArtworkOnly) private var showArtworkOnly: Bool = false
    @AppStorage(AppStorageKeys.queueInspectorVisible) private var queueInspectorVisible: Bool = false
    @AppStorage(AppStorageKeys.savedGroupID) private var savedGroupID: String?

    @State private var previousCount: Int = 0
    
#if targetEnvironment(macCatalyst)
    private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared
#endif
    
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SpeakerListScreen()
                    .navigationSplitViewColumnWidth(min: 320, ideal: 340, max: 400)
            } detail: {
                ContainerLargePlayerView()
            }
            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
            .withInspector(inspectorDestination: $router.inspectorSheet)
            .visionOrnament(router: router)
            .withAlert()
            .environment(router)
            .environment(sonosService)
            .environment(subscriptionService)
            .environment(alertService)
            .environment(musicSearchService)
            .environment(audioPlaybackService)
            .environment(playlistContainer)
            .environment(playHistoryService)
            .environment(miniPlayerManager)
            .onOpenURL(perform: handle)
            .onAppear {
                guard !AppBootstrapper.shared.didLaunch else { return }
                AppBootstrapper.shared.didLaunch = true
                AppBootstrapper.shared.bootstrap()

                Task { @MainActor in
                    try? await SubscriptionService.shared.checkSubscription()
                }

                SonosService.shared.groupsChanged = { groups in
                    guard subscriptionService.subscription.isActive else { return }
                    liveActivityManager.createActivity(shouldLoad: false)
                }

                SubscriptionService.shared.subscriptionUpdated = { subscription in
                    activeSubscription = subscription.isActive
#if canImport(WidgetKit)
                    if #available(visionOS 26.0, *) {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
#endif
                }

#if targetEnvironment(macCatalyst)
                if isMenuBarAppEnabled {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        do {
                            try await menuAppLaunchAtLoginManager.macUtils?.openClicMiniApp()
                        } catch {
                            print("Failed to launch ClicMini: \(error.localizedDescription)")
                        }
                    }
                }
#endif
                // Try and restore selected groupID
                if let savedGroupID = savedGroupID {
                    Task {
                        let startTime = Date.now
                        while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 5 {
                            try? await Task.sleep(for: .milliseconds(100))
                        }

                        if sonosService.sorted.contains(where: { $0.coordinatorID == savedGroupID }) {
                            router.selectedID = savedGroupID
                        }
                    }
                }

                // iPad/Mac: Auto-select first group and restore queue state
                if UIDevice.current.userInterfaceIdiom != .phone {
                    Task {
                        let startTime = Date.now
                        while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 5 {
                          try? await Task.sleep(for: .milliseconds(100))
                        }
                        try? await Task.sleep(for: .milliseconds(400))

                        // Auto-select first group if none selected (iPad initial launch)
                        if router.selectedID == nil {
                            sonosService.selectedGroup = sonosService.sorted.first
                            router.selectedID = sonosService.sorted.first?.coordinatorID
                        }

                        // Restore queue inspector if it was open
                        if queueInspectorVisible {
                            if let savedGroupID = savedGroupID,
                               let group = sonosService.sorted.first(where: { $0.coordinatorID == savedGroupID }) {

                                router.inspectorSheet = .queue(group: group)
                            } else if let selectedID = router.selectedID,
                                      let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) {
                                // Fall back to currently selected group
                                router.inspectorSheet = .queue(group: group)
                            } else if let firstGroup = sonosService.sorted.first {
                                // Fall back to first available group
                                router.inspectorSheet = .queue(group: firstGroup)
                            }
                        }
                    }
                }

                Task {
                    ClicAppShortcutProvider.updateAppShortcutParameters()
                }
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
                        router.selectedID = group.coordinatorID
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
        .onChange(of: router.selectedID) {
            if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                if let sheet = router.inspectorSheet, sheet.id == "search" {
                    router.inspectorSheet = .search(group: sonosService.sorted[group])
                } else if let sheet = router.inspectorSheet, sheet.id == "queue" {
                    router.inspectorSheet = .queue(group: sonosService.sorted[group])
                } else if let sheet = router.inspectorSheet, sheet.id == "browse" {
                    router.inspectorSheet = .browse(group: sonosService.sorted[group])
                }
            }
            
            savedGroupID = router.selectedID
        }
        .onChange(of: sonosService.groups) {
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
        .onChange(of: router.inspectorSheet) { oldValue, newValue in
            if UIDevice.current.userInterfaceIdiom != .phone  {
                queueInspectorVisible = (newValue?.id == "queue")
            }
        }
        .onChange(of: sonosService.isCellular) { oldValue, isCellular in
            if isCellular {
                router.selectedID = nil
                router.inspectorSheet = nil
                sonosService.clearDevices()
                alertService.showAlert(with: "On Cellular", imageName: "wifi.slash")
            } else if oldValue {
                // Coming back from cellular to WiFi - restart discovery
                sonosService.monitor()
            }
        }
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appSettings) {
                Button {
                    Router.main.presentedSheet = .settings()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button {
                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
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
                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                        if router.inspectorSheet != .browse(group: sonosService.sorted[group]) {
                            router.inspectorSheet = .browse(group: sonosService.sorted[group])
                        } else {
                            router.inspectorSheet = nil
                        }
                    }
                } label: {
                    Label("\(router.inspectorSheet?.id ?? "" == "browse" ? "Hide" : "Show") Browse", image: "home.fill")
                }
                .keyboardShortcut("b", modifiers: [])

                Button {
                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                        if router.inspectorSheet != .queue(group: sonosService.sorted[group]) {
                            router.inspectorSheet = .queue(group: sonosService.sorted[group])
                        } else {
                            router.inspectorSheet = nil
                        }
                    }
                } label: {
                    Label("\(router.inspectorSheet?.id ?? "" == "queue" ? "Hide" : "Show") Queue", systemImage: "list.dash")
                }
                .keyboardShortcut("q", modifiers: [])
                
                Button {
                    router.sheet(to: .settings(destination: .alarms))
                } label: {
                    Label("Show Alarms", systemImage: "alarm.fill")
                }
                .keyboardShortcut("a", modifiers: [.shift, .command])
                
                Toggle(isOn: $showArtworkOnly) {
                    Label("Album Cover Only", systemImage: "photo")
                    Text("Hide titles and controls.")
                }
                .keyboardShortcut("f", modifiers: [.shift, .command])
            }
            CommandMenu("Playback") {
                let groupSelected = router.selectedID.flatMap { id in
                    sonosService.sorted.first { $0.coordinatorID == id }?.nameWithCount
                } ?? "No Group Selected"
                ControlGroup(groupSelected) {
                    Button{
                        Task {
                            if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
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
                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                            Label {
                                Text("\(group.coordinatorRoom.isPlaying ? "Pause" : "Play")")
                            } icon: {
                                Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                            }
                        }
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    
                    Button {
                        Task {
                            if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                                HapticManager.shared.fireHaptic(.selection)
                                await sonosService.previous(ip: group.coordinatorRoom.ip)
                            }
                        }
                    } label: {
                        if router.selectedID != nil {
                            Label {
                                Text("Previous Track")
                            } icon: {
                                Image(systemName: "backward.fill")
                            }
                        }
                    }
                    .keyboardShortcut(.leftArrow)
                    .disabled(router.selectedID == nil)
                    
                    Button {
                        Task {
                            if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                                HapticManager.shared.fireHaptic(.selection)
                                await sonosService.next(ip: group.coordinatorRoom.ip)
                            }
                        }
                    } label: {
                        if router.selectedID != nil {
                            Label {
                                Text("Next Track")
                            } icon: {
                                Image(systemName: "forward.fill")
                            }
                        }
                    }
                    .keyboardShortcut(.rightArrow)
                    Button {
                        Task {
                            if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                                HapticManager.shared.fireHaptic(.selection)
                                await sonosService.setRelativeGroupVolume(ip: group.ip, volume: 5)
                            }
                        }
                    } label: {
                        if router.selectedID != nil {
                            Label {
                                Text("Volume Up")
                            } icon: {
                                Image(systemName: "speaker.wave.2.fill")
                            }
                        }
                    }
                    .keyboardShortcut(.upArrow)
                    
                    Button {
                        Task {
                            if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                                HapticManager.shared.fireHaptic(.selection)
                                await sonosService.setRelativeGroupVolume(ip: group.ip, volume: -5)
                            }
                        }
                    } label: {
                        if router.selectedID != nil {
                            Label {
                                Text("Volume Down")
                            } icon: {
                                Image(systemName: "speaker.wave.1.fill")
                            }
                        }
                    }
                    .keyboardShortcut(.downArrow)
                }

                Button {
                    Task {
                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                            HapticManager.shared.fireHaptic(.selection)
                            let newPosition = group.coordinatorRoom.track.playbackPosition + 15000
                            await sonosService.seek(to: newPosition, on: group)
                        }
                    }
                } label: {
                    Label("Seek Forward", systemImage: "goforward")
                }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(router.selectedID == nil)

                Button {
                    Task {
                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                            HapticManager.shared.fireHaptic(.selection)
                            let newPosition = max(0, group.coordinatorRoom.track.playbackPosition - 15000)
                            await sonosService.seek(to: newPosition, on: group)
                        }
                    }
                } label: {
                    Label("Seek Backward", systemImage: "gobackward")
                }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(router.selectedID == nil)

                Divider()

                Button {
                    Task {
                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                            var currentPlayMode = group.playMode
                            if currentPlayMode.contains(.shuffle) {
                                currentPlayMode.remove(.shuffle)
                            } else {
                                currentPlayMode.insert(.shuffle)
                            }
                            group.playMode = currentPlayMode
                            await sonosService.setPlayMode(group.ip, mode: currentPlayMode)
                        }
                    }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .keyboardShortcut("s")
                .disabled(router.selectedID == nil)

                Button {
                    Task {
                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                            var currentPlayMode = group.playMode
                            if !currentPlayMode.isRepeatEnabled {
                                currentPlayMode.insert(.repeatAll)
                            } else if currentPlayMode.isRepeatAllEnabled {
                                currentPlayMode.remove(.repeatAll)
                                currentPlayMode.insert(.repeatOne)
                            } else {
                                currentPlayMode.remove(.repeatOne)
                                currentPlayMode.remove(.repeatAll)
                            }
                            group.playMode = currentPlayMode
                            await sonosService.setPlayMode(group.ip, mode: currentPlayMode)
                        }
                    }
                } label: {
                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                        Label("Repeat", systemImage: group.playMode.contains(.repeatOne) ? "repeat.1" : "repeat")
                    } else {
                        Label("Repeat", systemImage: "repeat")
                    }
                }
                .keyboardShortcut("r")
                .disabled(router.selectedID == nil)

                Divider()

                Button {
                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                        router.sheet(to: .mediaDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
                    }
                } label: {
                    Label("Open Album", systemImage: "smallcircle.circle.fill")
                }
                .keyboardShortcut("i", modifiers: [.shift, .command])
                .disabled(router.selectedID == nil)

                Button {
                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
                        router.sheet(to: .artistDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
                    }
                } label: {
                    Label("Open Artist", systemImage: "music.mic")
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(router.selectedID == nil)
            }
//            CommandGroup(after: .windowArrangement) {
//                Button {
//                    openWindow(id: "mini")
//                } label: {
//                    Text("Mini Player")
//                }
//                .keyboardShortcut("0")
//            }
        }
//        Window(id: "mini") {
//            VStack {
//                MiniPlayerView()
//                    .environment(SelectedGroupService(group: sonosService.selectedGroup))
//                    .withEnvironments()
//            }
//        }
//        .windowResizability(.contentSize)
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
//        guard hasOnboarded else { return }
        switch scenePhase {
        case .active:
            sonosService.monitor()
            Task {
                let startTime = Date.now
                while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 10 {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard !sonosService.sorted.isEmpty else { return }
                sonosService.onServerListening()
            }
            
            if speedLaunchNowPlaying {
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    if sonosService.groups.isEmpty {
                        try? await sonosService.updateGroups()
                    }
                    try? await sonosService.updateGroupsCheckPlayback()
                    handle(URL(string: "clic://playing")!)
                }
            }
            
            if !subscriptionService.subscription.isActive {
                return
            }
            
            Task {
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
            if #available(visionOS 26.0, *) {
                WidgetCenter.shared.reloadAllTimelines()
            }
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

    @MainActor
    private func handle(_ url: URL) {
        Task {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            
            if sonosService.groups.isEmpty {
                try? await sonosService.updateGroups()
            }
            
            if components.host?.lowercased() == "playing" {
                let playingGroups = sonosService.groups.filter({ $0.coordinatorRoom.isPlaying || $0.TVMode })
                guard let group = playingGroups.first else {
                    return
                }
                router.selectedID = group.coordinatorID
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
                        router.selectedID = group.coordinatorID
                        if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                            router.presentedSheet = .search(group: group)
                        } else {
                            router.inspectorSheet = .search(group: group)
                        }
                    }
                    return
                }
                router.selectedID = group.coordinatorID
                if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                    router.presentedSheet = .search(group: group)
                } else {
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
                        router.selectedID = group.coordinatorID
                    }
                    return
                }
                router.selectedID = group.coordinatorID
            }
            
            // MARK: Add Back for queue
//            if let roomName = components.host {
//                guard let groupID = components.queryItems?.first(where: { $0.name == "id" })?.value else { return }
//
//                guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: groupID) else {
//                    return
//                }
//
//                if url.pathComponents.contains("queue") || components.queryItems?.contains(where: { $0.name == "showqueue" }) == true {
//                    router.selectedID = group.coordinatorID
//                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
//                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                        router.presentedSheet = .queue(group: sonosService.groups[groupIndex])
//                    } else {
//                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                        router.inspectorSheet = .queue(group: sonosService.groups[groupIndex])
//                    }
//                } else if url.pathComponents.contains("search") || components.queryItems?.contains(where: { $0.name == "showsearch" }) == true {
//                    router.selectedID = group.coordinatorID
//                    guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                    router.inspectorSheet = .search(group: sonosService.groups[groupIndex])
//                } else if url.pathComponents.contains("browse") || components.queryItems?.contains(where: { $0.name == "showbrowse" }) == true {
//                    router.selectedID = group.coordinatorID
//                    // Show browse
//                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
//                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                        router.presentedSheet = .browse(group: sonosService.groups[groupIndex])
//                    } else {
//                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                        router.inspectorSheet = .browse(group: sonosService.groups[groupIndex])
//                    }
//                } else {
//                    router.selectedID = group.coordinatorID
//                }
//                return
//            }

            if components.host?.lowercased() == "scene", let name = components.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
                guard let scene = scenes.first(where: { $0.name == name }) else { return }
                Task {
                    if let content = scene.playableContent {
                        alertService.showAlertContent(with: content, subtitle: "Running \(scene.name)", symbolName: "bolt.fill")
                    } else {
                        alertService.showAlert(with: "Running \(scene.name)")
                    }
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
                    router.selectedID = group.coordinatorID
                    router.presentedSheet = .groupScreen(group: group)
                }
                Task {
                    try await sonosService.load(useCache: true)
                    if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                        router.selectedID = group.coordinatorID
                        router.presentedSheet = .groupScreen(group: group)
                        return
                    }
                }
            }
            
            if components.host?.lowercased() == "services" {
                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
            }
        }
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
            builder.remove(menu: .newScene)
            builder.remove(menu: .open)
            builder.remove(menu: .openRecent)
            builder.remove(menu: .document)

            // Add New Playlist to File menu
            let newPlaylistCommand = UIKeyCommand(
                title: "New Playlist",
                image: UIImage(systemName: "music.note.list"),
                action: #selector(newPlaylist),
                input: "n",
                modifierFlags: .command
            )

            // Add to Last Playlist command (dynamic title)
            let lastPlaylistTitle = UserDefaults.standard.string(forKey: AppStorageKeys.lastPlaylistTitle)
            let addToLastPlaylistAction: UIMenuElement

            if let title = lastPlaylistTitle {
                addToLastPlaylistAction = UIKeyCommand(
                    title: "Add to \(title)",
                    image: UIImage(systemName: "plus"),
                    action: #selector(addToLastPlaylist),
                    input: "s",
                    modifierFlags: [.shift, .command]
                )
            } else {
                addToLastPlaylistAction = UIAction(title: "Add to Last Playlist", attributes: .disabled) { _ in }
            }

            // Add to Playlist submenu with deferred loading
            let addToPlaylistDeferred = UIDeferredMenuElement.uncached { completion in
                Task { @MainActor in
                    let sonosService = SonosService.shared
                    let alertService = AlertService.shared

                    // Get current track from selected group
                    guard let selectedID = Router.main.selectedID,
                          let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) else {
                        completion([
                            UIAction(title: "No Track Playing", attributes: .disabled) { _ in }
                        ])
                        return
                    }

                    let currentTrack = group.coordinatorRoom.track
                    let playlists = await sonosService.sonosPlaylists()

                    var menuItems: [UIMenuElement] = []

                    // Add existing playlists
                    for playlist in playlists {
                        let action = UIAction(title: playlist.title) { _ in
                            Task { @MainActor in
                                alertService.showAlertContent(with: currentTrack.toPlayable, subtitle: "Added to \(playlist.title)", symbolName: "plus")
                                await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: currentTrack.toPlayable)

                                // Save as last used playlist and rebuild menu
                                UserDefaults.standard.set(playlist.id, forKey: AppStorageKeys.lastPlaylistID)
                                UserDefaults.standard.set(playlist.title, forKey: AppStorageKeys.lastPlaylistTitle)
                                UIMenuSystem.main.setNeedsRebuild()

                                // Set up tap to navigate to playlist
                                alertService.alert.handleTap = {
                                    Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                                }
                            }
                        }
                        menuItems.append(action)
                    }

                    completion(menuItems)
                }
            }

            let addToPlaylistMenu = UIMenu(
                title: "Add to Playlist",
                image: UIImage(systemName: "text.badge.plus"),
                children: [addToPlaylistDeferred]
            )

            let fileMenuItems = UIMenu(
                title: "",
                options: .displayInline,
                children: [newPlaylistCommand, addToLastPlaylistAction, addToPlaylistMenu]
            )

            builder.insertChild(fileMenuItems, atStartOfMenu: .file)
        }
    }

    @objc func newPlaylist() {
        Router.main.presentedSheet = .newPlaylist()
    }

    @objc func addToLastPlaylist() {
        let sonosService = SonosService.shared
        let alertService = AlertService.shared

        guard let lastPlaylistID = UserDefaults.standard.string(forKey: AppStorageKeys.lastPlaylistID),
              let lastPlaylistTitle = UserDefaults.standard.string(forKey: AppStorageKeys.lastPlaylistTitle) else {
            alertService.showAlert(with: "No Recent Playlist", imageName: "exclamationmark.triangle")
            return
        }

        guard let selectedID = Router.main.selectedID,
              let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) else {
            alertService.showAlert(with: "No Group Selected", imageName: "exclamationmark.triangle")
            return
        }

        let currentTrack = group.coordinatorRoom.track.toPlayable

        Task { @MainActor in
            alertService.showAlertContent(with: currentTrack, subtitle: "Added to \(lastPlaylistTitle)", symbolName: "plus")
            await sonosService.addToPlaylist(playlistID: lastPlaylistID, playableContent: currentTrack)

            // Set up tap to navigate to playlist
            let playlists = await sonosService.sonosPlaylists()
            if let playlist = playlists.first(where: { $0.id == lastPlaylistID }) {
                alertService.alert.handleTap = {
                    Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                }
            }
        }
    }
}

class ClicSceneDelegate: NSObject, UIWindowSceneDelegate {
    var toolbarDelegate = ToolbarDelegate()
    #if targetEnvironment(macCatalyst)
    private var windowSizeObserver: WindowSizeObserver?
    #endif
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
#if targetEnvironment(macCatalyst)
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
        
        // Set size restrictions
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 500)
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: 2000, height: 1500)
        
        // Restore saved window frame
        if let savedFrame = WindowFrameStore.savedFrame {
            let geometry = UIWindowScene.GeometryPreferences.Mac(systemFrame: savedFrame)
            windowScene.requestGeometryUpdate(geometry)
        }
        
        // Start observing window size changes
        windowSizeObserver = WindowSizeObserver(windowScene: windowScene)
#endif
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
#if targetEnvironment(macCatalyst)
        windowSizeObserver = nil
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
