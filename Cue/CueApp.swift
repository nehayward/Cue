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
import CoreSpotlight
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Tab bar accessory mini player for wherever the route points: this device,
/// or the Sonos group chosen in the route button. Tapping the track opens the
/// matching full player; the trailing controls act in place.
struct MusicPlaybackView: View {
    @Environment(\.tabViewBottomAccessoryPlacement) var placement
    /// Owned by `CueApp`, not by this view. The tab bar accessory is hosted
    /// outside the tab content and gets re-created when its placement changes
    /// or the scene comes back to the foreground — `@State` here reset to
    /// `false` on that rebuild and took the presented player down with it.
    @Binding var showPlayer: Bool
    /// Owned by `CueApp` too, because the zoom's other half — the
    /// `fullScreenCover` — is declared up there now.
    let zoomNamespace: Namespace.ID

    private var playback: LocalPlaybackService { .shared }
    /// Singletons rather than the environment: the accessory is hosted
    /// outside what `withEnvironments()` installs on the tab content.
    private var route: PlaybackRoute { .shared }
    private var sonosService: SonosService { .shared }

    var body: some View {
        HStack(spacing: 12) {
            if let group = route.group {
                groupContent(group)
            } else {
                deviceContent
            }

            // Always present, playing or not: the route is set ahead of Play,
            // which is the whole point of it no longer asking.
            PlaybackRouteButton()
                .buttonStyle(.plain)
                .font(.title3)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: 500, maxHeight: 120)
    }

    // MARK: - This device

    @ViewBuilder
    private var deviceContent: some View {
        Button {
            showPlayer.toggle()
        } label: {
            HStack(spacing: 12) {
                if let item = playback.nowPlaying {
                    ContentArtworkView(content: item, showMusicSource: false)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text(item.title)
                            .font(.callout.bold())
                            .lineLimit(1)
                        if placement != .inline {
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                    Text("Not Playing")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .zoomSource(.miniPlayer, in: zoomNamespace)

        if playback.isActive {
            Button {
                playback.togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .font(.title3)

            if placement != .inline {
                Button {
                    playback.next()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .font(.title3)
            }
        }
    }

    // MARK: - A speaker

    /// The same row for a Sonos group: its current track, and transport that
    /// acts on the speaker. `GroupRoom` is `@Observable`, so the pushed track
    /// and playing state redraw this in place.
    @ViewBuilder
    private func groupContent(_ group: GroupRoom) -> some View {
        let room = group.coordinatorRoom
        let track = room.track

        Button {
            showPlayer.toggle()
        } label: {
            HStack(spacing: 12) {
                if route.isSwitching {
                    ProgressView()
                        .frame(width: 40, height: 40)
                } else if !track.isEmpty {
                    ContentArtworkView(content: track.toPlayable, showMusicSource: false)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(track.isEmpty ? "Not Playing" : track.song)
                        .font(track.isEmpty ? .callout : .callout.bold())
                        .foregroundStyle(track.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    if placement != .inline {
                        Text(group.nameWithCount)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .zoomSource(.miniPlayer, in: zoomNamespace)

        if !track.isEmpty {
            Button {
                Task {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    await sonosService.togglePlayPause(for: group)
                }
            } label: {
                Image(systemName: room.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: room.isTransitioning)
            }
            .buttonStyle(.plain)
            .font(.title3)

            if placement != .inline {
                Button {
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        room.playbackPosition = 0
                        await sonosService.next(ip: group.ip)
                        try? await sonosService.updateGroups(from: [group])
                    }
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .font(.title3)
                .disabled(!group.availableActions.contains(.next))
            }
        }
    }
}

/// What the accessory's `fullScreenCover` shows: the local player, or the
/// Sonos player for the group the route points at. Decided in a body of its
/// own so the route is observed — a change while the cover is up swaps the
/// player rather than leaving the old one behind.
private struct PresentedPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    /// The Sonos player's own navigation: the artist and album buttons push
    /// their screens here, inside the cover, rather than into a tab.
    @State private var playerRouter = Router()

    private var route: PlaybackRoute { .shared }

    var body: some View {
        if let group = route.group {
            @Bindable var playerRouter = playerRouter
            NavigationStack(path: $playerRouter.path) {
                LargePlayerView(coordinatorID: group.coordinatorID)
                    .withAppRouter()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .accessibilityLabel("Close")
                        }
                    }
            }
            .withSheetDestinations(sheetDestinations: $playerRouter.presentedSheet)
            .environment(playerRouter)
            .withEnvironments()
        } else {
            PlayerView()
        }
    }
}

@main
struct CueApp: App {
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
    private var favoriteRatingCache = FavoriteRatingCache.shared

    @CloudStorage(CloudKeys.hasSubscription) private var activeSubscription: Bool = false
    @CloudStorage(CloudKeys.scenes) var scenes: [SonosScene] = []
    
    @AppStorage(GroupStorageKeys.hasOnboarded, store: GroupStorageKeys.storage) private var hasOnboarded: Bool = false
    @AppStorage("CueMiniEnabled") private var isMenuBarAppEnabled: Bool = true
    @AppStorage(AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false
    @AppStorage(AppStorageKeys.showArtworkOnly) private var showArtworkOnly: Bool = false
    @AppStorage(AppStorageKeys.savedGroupID) private var savedGroupID: String?

    @State private var previousCount: Int = 0
    
#if targetEnvironment(macCatalyst)
    private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared

    /// Composite key driving `.task(id:)` for the dock menu. Reading these
    /// properties during body eval registers SwiftUI observation, so any
    /// change re-fires the refresh task.
    private var dockRefreshKey: DockMenuCoordinator.RefreshKey {
        let group = router.selectedID.flatMap { id in sonosService.sorted.first(where: { $0.coordinatorID == id }) }
        return .init(
            selectedGroupID: router.selectedID,
            trackUnique: group?.coordinatorRoom.track.unique,
            isPlaying: group?.coordinatorRoom.isPlaying ?? false,
            availableGroupIDs: sonosService.sorted.map { $0.coordinatorID }
        )
    }
#endif
    
    /// `@AppStorage`, not `@State`: `PlayerView` reads the same key, so the
    /// queue panel is shown or hidden in both places at once instead of each
    /// keeping its own idea. Persisting across launches comes along with it,
    /// which is the behaviour a panel toggle wants anyway.
    @AppStorage(AppStorageKeys.queueInspectorVisible) private var showInspector: Bool = false
    /// Shared by the zoom's two halves: the source in the tab bar accessory and
    /// the `fullScreenCover` on the `TabView` below.
    @Namespace private var zoomNamespace

    /// The providers the user added to the tab view. Each is a tab of its
    /// own and, on iPad and Mac, a sidebar section split into its
    /// collections. Singletons rather than the environment: the sidebar's
    /// bottom bar reads these too, and it is hosted outside what
    /// `withEnvironments()` installs on the tab content.
    @State private var tabProviders = TabProviderStore.shared
    @State private var coreFeatures = CoreFeatures.shared
    /// The sidebar edits the system makes for the user — hiding and
    /// reordering the provider tabs — kept across launches.
    @AppStorage(AppStorageKeys.tabViewCustomization) private var tabCustomization = TabViewCustomization()
    /// Sheets the tab view itself presents (Customize Tabs, a provider's
    /// management), as opposed to the ones each tab's router owns.
    @State private var tabSheet: SheetDestination?

    /// Added providers that are switched on in Services. One turned off
    /// there loses its tabs but keeps its place, so it comes back where it
    /// was.
    private var visibleTabProviders: [TabProvider] {
        tabProviders.visibleProviders(enabledIn: coreFeatures)
    }

    /// The sidebar header's plus: the providers switched on in Services
    /// that aren't tabs yet, and the full arrangement behind them.
    private var addProviderMenu: some View {
        let available = tabProviders.availableProviders(enabledIn: coreFeatures)

        return Menu {
            ForEach(available, id: \.self) { service in
                Button {
                    tabProviders.add(service)
                } label: {
                    // Text then mark, as the Browse tab's provider menu
                    // lays its rows out.
                    HStack {
                        Text("Add \(service.title)")
                        service.image
                    }
                }
            }
            if !available.isEmpty {
                Divider()
            }
            Button {
                tabSheet = .customizeTabs
            } label: {
                Label("Customize Tabs…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("Add Provider", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Add Provider")
    }

    /// A provider's tabs: one of its own for the tab bar, and a sidebar
    /// section holding a tab per switched-on collection. The two never show
    /// together — the root tab is hidden from the sidebar, the collection
    /// tabs from the tab bar — so iPhone gets a single "Plex" tab listing
    /// the same collections that iPad and Mac show as a Plex section. Every
    /// tab carries a `customizationID` so the sidebar's edit mode can hide
    /// and reorder them; Search and Browse carry none and stay put.
    @TabContentBuilder<AppTab>
    private func providerTabs(for provider: TabProvider) -> some TabContent<AppTab> {
        let service = provider.service
        // iPhone has only the tab bar, and its More list shows every tab
        // whatever `defaultVisibility` says — so the phone gets the one tab
        // and no section at all.
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone

        Tab(value: AppTab.provider(service)) {
            Screens.providerRoot(provider)
        } label: {
            // A bare `Image`: the tab bar pulls the image out of the label
            // and draws nothing for a sized or tinted view around it.
            Label {
                Text(service.title)
            } icon: {
                service.tabImage
            }
        }
        .customizationID(service.tabCustomizationID)
        .defaultVisibility(isPhone ? .visible : .hidden, for: .sidebar)

        if !isPhone {
            TabSection {
                ForEach(provider.collections, id: \.self) { collection in
                    Tab(collection.title, systemImage: collection.systemImage, value: AppTab.providerCollection(service, collection)) {
                        Screens.providerCollection(provider, collection)
                    }
                    .customizationID(service.tabCustomizationID(for: collection))
                    .defaultVisibility(.hidden, for: .tabBar)
                }
            } header: {
                Text(service.title)
            }
            // No section action: the sidebar's own Edit handles hiding and
            // reordering, and the Customize sheet is reachable from Home
            // and the plus menu.
        }
    }

    var body: some Scene {
        WindowGroup {
            @Bindable var router = router
            TabView(selection: $router.selectedTab.reselecting(perform: router.handleReselection)) {
                // No `role: .search`. The role exists so the system can hoist a
                // `.searchable` out of the tab, and it renders the tab as a
                // separate search affordance rather than a peer — which is why
                // it never took the selected appearance. `SearchScreen` draws
                // its own field in the navigation bar again, so the role has
                // nothing left to hoist.
                Tab("Home", systemImage: "house", value: AppTab.home) {
                    Screens.home
                }

                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                    Screens.search
                }
                
                Tab("Browse", systemImage: "square.grid.2x2", value: AppTab.browse) {
                    Screens.browse
                }

                // One tab per added provider, plus its sidebar section. A
                // provider the user turned off in Services drops out here
                // without losing its place in the list.
                ForEach(visibleTabProviders) { provider in
                    providerTabs(for: provider)
                }
            }
            .tabViewCustomization($tabCustomization)
            .onChange(of: visibleTabProviders) { _, providers in
                // A provider that left the tab view takes its selection with
                // it; a `TabView` whose selection names no tab shows nothing.
                if let service = router.selectedTab.provider,
                   !providers.contains(where: { $0.service == service }) {
                    router.selectedTab = .home
                }
            }
            .withSheetDestinations(sheetDestinations: $tabSheet)
            // The queue panel is inside each tab (`Screens`), not out here:
            // wrapped around the whole `TabView` it took its width from the
            // sidebar's, which then had to overlay the content instead of
            // sitting beside it.
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                MusicPlaybackView(showPlayer: $router.isPlayerPresented, zoomNamespace: zoomNamespace)
            }
//            // Above the tabs, not in one of them: a toolbar belongs to the
//            // navigation stack of whichever tab is on screen, so the only way
//            // to keep one field in every tab is to host it out here.
//            .safeAreaInset(edge: .top) {
//                GlobalSearchField(selectedTab: $selectedTab)
//            }
            .tabViewSidebarHeader {
                HStack(spacing: 10) {
                    Image("CueIconGlass")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    Text("Cue")
                        .font(.title3.bold())
                    Spacer(minLength: 0)
                    // The plus that adds a provider to the sidebar lives up
                    // here by the app name, where it can't be missed.
                    addProviderMenu
                        .tint(Color("Accent"))
                }
                .padding(.vertical, 4)
            }
            .tabViewSidebarFooter {
                let count = sonosService.sorted.count
                Label(
                    count == 1 ? "1 Speaker Group" : "\(count) Speaker Groups",
                    systemImage: count == 0 ? "hifispeaker.slash" : "hifispeaker.2"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .background(.red)
            }
            .tabViewSidebarBottomBar {
                // The toggle was in the top safe-area inset, where the sidebar
                // and tab bar draw over it and swallow the click. This slot is
                // system-managed, so nothing overlaps it.
                Button {
                    withAnimation {
                        showInspector.toggle()
                    }
                } label: {
                    Label(
                        showInspector ? "Hide Queue" : "Show Queue",
                        systemImage: "sidebar.trailing"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .tint(Color("Accent"))
            }
            // The sidebar's selection highlight is drawn in the tint, so this
            // is what takes it off accent-teal. A TabView sidebar has no way to
            // colour the row's label separately from its fill, so this gets the
            // subtle neutral capsule but not Music.app's accent-coloured label.
            // The tint reaches the whole TabView, which is why the tab content
            // and the bottom bar put the real accent back — `Color("Accent")`
            // by name, since `.accentColor` now resolves to this tint.
//            .tint(Color.primary.opacity(0.12))
            .withEnvironments()
            .environment(favoriteRatingCache)
            // Presented from the `TabView`, not from inside the tab bar
            // accessory. The system re-hosts that accessory when its placement
            // changes or the scene returns to the foreground, and a
            // `fullScreenCover` declared there is re-created with it — which
            // tore the player down and put it back on every background/
            // foreground round trip. The `TabView` is stable, so the
            // presentation survives.
            //
            // It also removes the reason the zoom needed guarding: the morph
            // only happens when the cover presents, and the cover no longer
            // re-presents behind the user's back.
            .fullScreenCover(isPresented: $router.isPlayerPresented) {
                PresentedPlayerView()
                    .presentationBackgroundInteraction(.enabled)
                    .zoomTransition(from: .miniPlayer, in: zoomNamespace)
            }
            .tabViewStyle(.sidebarAdaptable)
            .onOpenURL(perform: handle)
            .onAppear {
                SonosService.shared.monitor()
            }
            //            .withAlert()
        }
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
//                            try await menuAppLaunchAtLoginManager.bridge?.openCueMiniApp()
//                        } catch {
//                            print("Failed to launch CueMini: \(error.localizedDescription)")
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
//                    CueAppShortcutProvider.updateAppShortcutParameters()
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
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            // Printed like the other two: without it a scene trace reads
            // `Inactive … Monitoring!` with no way to tell whether the app came
            // back or something else restarted the pulse. That ambiguity is what
            // hid `stopMonitoringOffScreen`'s bug.
            print("Active")
            // Don't poke the network (which triggers the Local Network
            // permission prompt) until onboarding has surfaced the explanation
            // screen and the user has tapped Continue. WelcomeScreen kicks off
            // `monitor()` on dismiss.
            guard hasOnboarded, !OnboardingDebug.forceShow else { return }
            // The network may have changed while backgrounded (e.g. home →
            // friend's house). Re-race known IPs + discovery on the next poll
            // instead of blocking on a now-stale cached IP. Cheap: an unchanged
            // network still wins in ms, and the flag re-verifies after one load.
            sonosService.invalidateVerifiedConnection()
            // Re-opened before `monitor()`, and before any view `.task` that
            // fires as the app comes back can call it — this runs first on the
            // activation.
            sonosService.allowsMonitoring = true
            sonosService.monitor()
#if targetEnvironment(macCatalyst)
            // Window is open — live monitoring + `.task(id:)` keep the dock
            // menu fresh, so the background poll isn't needed.
            DockMenuCoordinator.shared.stopBackgroundRefresh()
#endif
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
                    handle(URL(string: "cue://playing")!)
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
            stopMonitoringOffScreen(scenePhase)
        case .background:
            print("Background")
            stopMonitoringOffScreen(scenePhase)
#if targetEnvironment(macCatalyst)
            // Monitoring is now cancelled, so the cached model freezes. Poll
            // the selected group on a slow cadence to keep the dock menu
            // current (it's built synchronously and can't fetch on open).
            DockMenuCoordinator.shared.startBackgroundRefresh()
#endif
        @unknown default:
            break
        }
    }

    /// Stops the SOAP pulse and the volume watcher, which exist to feed on-screen
    /// UI and are the app's most expensive recurring work — `load()` plus a
    /// per-group sweep every 500–800 ms.
    ///
    /// Called for `.inactive` as well as `.background`, because **the phone
    /// locking with Cue frontmost does not reliably reach `.background`**. With
    /// the Lock Screen card's audio session held the scene often parks at
    /// `.inactive` instead, and keying the teardown on `.background` alone left
    /// both loops polling with the screen off — sometimes for the whole time the
    /// phone was locked. The scene trace behind that bug reads
    /// `Inactive, Inactive, Inactive` with no `Background` at all.
    ///
    /// A transient `.inactive` — a notification banner, a Control Centre pull,
    /// the app switcher — costs one `monitor()` restart on the way back, the
    /// same as any foreground return. That is cheap, and much cheaper than the
    /// case this exists to stop.
    ///
    /// Not on iPad: there, `.inactive` is also what a *visible* window in Split
    /// View or Stage Manager reports when it merely isn't the focused one, and
    /// freezing a window the user can see would be a real regression. iPad keeps
    /// the old `.background`-only behaviour until there's a signal that
    /// separates "not focused" from "not on screen".
    ///
    /// Guarded on onboarding for the same reason `.active` is: the Local Network
    /// permission prompt makes the scene `.inactive` while it's up, and `.active`
    /// deliberately doesn't restart monitoring before onboarding is done — so
    /// tearing down here would stop discovery with nothing to start it again.
    @MainActor
    private func stopMonitoringOffScreen(_ phase: ScenePhase) {
        guard hasOnboarded, !OnboardingDebug.forceShow else { return }
        if phase == .inactive, UIDevice.current.userInterfaceIdiom == .pad { return }

        // Shut the gate before cancelling, not after: cancelling only stops the
        // loops that are running, and `monitor()` is called from a dozen places
        // — a Search button, several view `.task`s, the cellular-recovery
        // handler — any of which would restart them behind a locked screen.
        // `SonosService.allowsMonitoring` is what makes this a guarantee rather
        // than a race.
        sonosService.allowsMonitoring = false
        sonosService.sonosPulse.cancel()
        sonosService.watcher.cancel()
    }

    @MainActor
    private func handle(_ url: URL) {
        Task {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            
            if sonosService.groups.isEmpty {
                try? await sonosService.updateGroups()
            }
            
            if components.host?.lowercased() == "playing" {
                guard let group = await sonosService.firstPlayingGroup() else {
                    return
                }
                router.selectedID = group.coordinatorID
                return
            }
            
            // The share extension's Device destination. It can't play locally
            // itself — `ApplicationMusicPlayer` doesn't run in an app extension,
            // and its process ends with the sheet — so it forwards the content
            // here with `device=1` on the usual play/resolve link.
            if components.queryItems?.contains(where: { $0.name == "device" && $0.value == "1" }) == true,
               ["play", "resolve"].contains(components.host?.lowercased() ?? "") {
                let position = components.queryItems?
                    .first { $0.name == "position" }?.value
                    .flatMap(QueuePosition.init(linkValue:)) ?? .now
                let source: URL? = if components.host?.lowercased() == "resolve" {
                    components.queryItems?.first { $0.name == "url" }?.value.flatMap(URL.init(string:))
                } else {
                    Self.strippingHandoffQuery(url)
                }
                guard let source else { return }
                await playOnDevice(from: source, position: position)
                return
            }

            if components.host?.lowercased() == "alarms" {
                router.presentedSheet = .settings(destination: .alarms)
                return
            }
            
            if components.host?.lowercased() == "subscribe" {
                router.presentedFullScreenCover = .paywall
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

            if components.host?.lowercased() == "view", let url = components.url {
                Task {
                    guard let content = await sonosService.getContent(from: url) else { return }
                    if content.content.type == .artist || content.content.type == .libraryArtist {
                        router.sheet(to: .artistDetail(content: content, group: nil))
                    } else if content.content.type.isRadio {
                        // Stations have no detail screen — open the play sheet
                        // so the user can pick a room.
                        router.sheet(to: .playMedia(url: url))
                    } else {
                        router.sheet(to: .mediaDetail(content: content, group: nil))
                    }
                }
            }

            // Fallback for the share extension: when it can't resolve the
            // shared link itself, it forwards the original URL via
            // cue://resolve?url=<encoded>. The main app has full
            // SonosService/MusicKit access and can resolve it here.
            if components.host?.lowercased() == "resolve",
               let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let originalURL = URL(string: raw) {
                router.sheet(to: .playMedia(url: originalURL))
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

    /// Strips the routing-only parameters back off, so what's left is the plain
    /// `cue://play/...` link `getContent(from:)` already knows how to resolve.
    private static func strippingHandoffQuery(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let remaining = (components.queryItems ?? []).filter { !["device", "position"].contains($0.name) }
        components.queryItems = remaining.isEmpty ? nil : remaining
        return components.url ?? url
    }

    /// Plays shared content on this device rather than a Sonos group. The
    /// extension only screens out what can *never* play here, so this is where
    /// the real test happens — anything the local queue won't take (Spotify and
    /// friends, a Plex track with no stream URL) falls back to the room picker
    /// instead of failing silently.
    private func playOnDevice(from url: URL, position: QueuePosition) async {
        guard let content = await sonosService.getContent(from: url) else {
            router.sheet(to: .playMedia(url: url))
            return
        }

        do {
            try await LocalPlaybackService.shared.enqueue(content, at: position)
            alertService.showAlertContent(
                with: content,
                subtitle: "Playing on this device",
                symbolName: "iphone.radiowaves.left.and.right"
            )
        } catch LocalPlaybackService.LocalPlaybackError.nothingPlayable {
            // Nothing here can play locally, so fall back to picking a speaker.
            // The sheet applies the same test and will hide its own Device row,
            // which is what we want — offering it again would only fail again.
            router.sheet(to: .playMedia(url: url))
        } catch {
            alertService.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
        }
    }
}


/// Transport buttons for the "Playback" command menu. Extracted into its own
/// View because inlining all five buttons (each with conditional labels and
/// async closures) pushed the `Commands` builder past the type-checker's
/// reasonable-time limit.
private struct PlaybackTransportControls: View {
    let router: Router
    let sonosService: SonosService

    private var selectedGroup: GroupRoom? {
        guard let id = router.selectedID else { return nil }
        return sonosService.sorted.first { $0.coordinatorID == id }
    }

    var body: some View {
        ControlGroup(selectedGroup?.nameWithCount ?? "No Group Selected") {
            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    if group.coordinatorRoom.isPlaying {
                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                }
            } label: {
                let playing = selectedGroup?.coordinatorRoom.isPlaying ?? false
                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])

            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    // Twin of the transport buttons in LargePlayerView: a
                    // deliberate skip snaps the artwork over rather than
                    // crossfading it.
                    router.beginSkipWindow()
                    await sonosService.previous(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Label("Previous Track", systemImage: "backward.fill")
            }
            .keyboardShortcut(.leftArrow)
            .disabled(router.selectedID == nil)

            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    group.coordinatorRoom.playbackPosition = 0
                    router.beginSkipWindow()
                    await sonosService.next(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Label("Next Track", systemImage: "forward.fill")
            }
            .keyboardShortcut(.rightArrow)
            .disabled(router.selectedID == nil)

            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    await sonosService.setRelativeGroupVolume(ip: group.ip, volume: 5)
                }
            } label: {
                Label("Volume Up", systemImage: "speaker.wave.2.fill")
            }
            .keyboardShortcut(.upArrow)
            .disabled(router.selectedID == nil)

            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    await sonosService.setRelativeGroupVolume(ip: group.ip, volume: -5)
                }
            } label: {
                Label("Volume Down", systemImage: "speaker.wave.1.fill")
            }
            .keyboardShortcut(.downArrow)
            .disabled(router.selectedID == nil)
        }
    }
}

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if targetEnvironment(macCatalyst)
        // macOS auto-injects "Start Dictation" and "Emoji & Symbols" into any Edit menu. Opt out so
        // ours carries only Undo/Redo. (AutoFill is removed via the menu builder.)
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
        #endif
        // The continued-processing task's launch handler has to be in place
        // before a download batch submits it.
        ContinuedDownloadTask.shared.register()
        // A Files scan gets the same card: progress on the Lock Screen and
        // the app kept running until it's done.
        Task { @MainActor in
            FilesLibraryService.shared.onScanStarted = {
                ContinuedDownloadTask.shared.trackScan(folderName: FilesLibraryService.shared.folderName ?? "Music")
            }
        }
        return true
    }

    /// The system relaunched (or woke) the app because the download
    /// session has events to deliver. Handing the completion handler to the
    /// manager makes it recreate the session, which drains the events; it
    /// calls the handler once they're done.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            DownloadManager.shared.backgroundCompletionHandler = completionHandler
        }
    }

    func application(
       _ application: UIApplication,
       configurationForConnecting connectingSceneSession: UISceneSession,
       options: UIScene.ConnectionOptions
     ) -> UISceneConfiguration {
         if let shortcutItem = options.shortcutItem {
             if shortcutItem.type == "com.cue.search" {
                 Task { @MainActor in
                     // MARK: Delay for Toolbar
                     try await Task.sleep(for: .milliseconds(200))
                     Router.main.path.removeAll()
                     Router.main.presentedSheet = .search()
                 }
             }
         }

       let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
       sceneConfig.delegateClass = CueSceneDelegate.self // 👈🏻
       return sceneConfig
     }
    
    override func buildMenu(with builder: UIMenuBuilder) {
        /// Only operate on the main menu bar.
        if builder.system == .main {
            // Remove the system Edit menu entirely — macOS force-injects AutoFill / Start Dictation /
            // Emoji & Symbols into any Edit menu. Undo/Redo live in a dedicated Playlist menu instead.
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
            let addToLastPlaylistAction: UIMenuElement

            if let last = LastPlaylist.current {
                addToLastPlaylistAction = UIKeyCommand(
                    title: "Add to \(last.title)",
                    image: last.service.uiImage ?? UIImage(systemName: "text.badge.plus"),
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
                    let musicSearchService = MusicSearchService.shared

                    // Get current track from selected group
                    guard let selectedID = Router.main.selectedID,
                          let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) else {
                        completion([
                            UIAction(title: "No Track Playing", attributes: .disabled) { _ in }
                        ])
                        return
                    }

                    let track = group.coordinatorRoom.track.toPlayable

                    // Adds `track` to `playlist`, dispatching to Sonos or the streaming service.
                    func action(for playlist: PlayableContent) -> UIAction {
                        UIAction(title: playlist.title, image: playlist.content.service.uiImage) { _ in
                            Task { @MainActor in
                                let success: Bool
                                if playlist.content.service == .library {
                                    await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: track)
                                    success = true
                                } else {
                                    success = await musicSearchService.addToServicePlaylist(track: track, playlist: playlist)
                                }
                                guard success else {
                                    alertService.showAlert(with: "Couldn’t add to \(playlist.title)", imageName: "exclamationmark.triangle")
                                    return
                                }
                                alertService.showAlertContent(with: track, subtitle: "Added to \(playlist.title)", symbolName: "plus")
                                LastPlaylist.save(playlist)
                                alertService.alert.handleTap = {
                                    Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                                }
                            }
                        }
                    }

                    var menuItems: [UIMenuElement] = []

                    // The track's own streaming-service playlists (Apple Music / Spotify / Plex / Deezer).
                    let service = track.content.service
                    if [.apple, .spotify, .plex, .deezer, .subsonic, .files].contains(service),
                       [.track, .libraryTrack].contains(track.content.type) {
                        let servicePlaylists = await musicSearchService.userPlaylists(for: service)
                        if !servicePlaylists.isEmpty {
                            menuItems.append(UIMenu(title: service.title, options: .displayInline, children: servicePlaylists.map(action)))
                        }
                    }

                    // Sonos playlists accept any track.
                    let sonosPlaylists = await sonosService.sonosPlaylists()
                    if !sonosPlaylists.isEmpty {
                        menuItems.append(UIMenu(title: "Sonos", options: .displayInline, children: sonosPlaylists.map(action)))
                    }

                    if menuItems.isEmpty {
                        menuItems = [UIAction(title: "No Playlists", attributes: .disabled) { _ in }]
                    }

                    completion(menuItems)
                }
            }

            let addToPlaylistMenu = UIMenu(
                title: "Add to Playlist",
                image: UIImage(systemName: "text.badge.plus"),
                children: [addToPlaylistDeferred]
            )

            // A dedicated Playlist menu gathers every playlist action plus Undo/Redo, on all
            // platforms — so ⌘Z works with a hardware keyboard on iPad/iPhone too, not just Catalyst.
            // (We don't reuse the Edit menu: macOS injects AutoFill/Dictation/Emoji into it.)
            // Undo/Redo route through the responder chain (playlistUndo/playlistRedo) and enable via
            // canPerformAction.
            let undoCommand = UIKeyCommand(title: "Undo", action: #selector(playlistUndo), input: "z", modifierFlags: .command)
            let redoCommand = UIKeyCommand(title: "Redo", action: #selector(playlistRedo), input: "z", modifierFlags: [.command, .shift])
            let playlistMenu = UIMenu(title: "Playlist", identifier: UIMenu.Identifier("com.cue.playlistMenu"), children: [
                UIMenu(title: "", options: .displayInline, children: [newPlaylistCommand, addToLastPlaylistAction, addToPlaylistMenu]),
                UIMenu(title: "", options: .displayInline, children: [undoCommand, redoCommand])
            ])
            builder.insertSibling(playlistMenu, afterMenu: .file)
        }
    }

    /// Drives the foreground playlist editor's undo, routed from the Playlist menu / ⌘Z.
    @objc func playlistUndo() {
        PlaylistUndoMenuBridge.shared.editor?.undo()
    }

    /// Drives the foreground playlist editor's redo, routed from the Playlist menu / ⌘⇧Z.
    @objc func playlistRedo() {
        PlaylistUndoMenuBridge.shared.editor?.redo()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(playlistUndo):
            return PlaylistUndoMenuBridge.shared.editor?.canUndo ?? false
        case #selector(playlistRedo):
            return PlaylistUndoMenuBridge.shared.editor?.canRedo ?? false
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    @objc func newPlaylist() {
        Router.main.presentedSheet = .newPlaylist()
    }

    @objc func addToLastPlaylist() {
        let sonosService = SonosService.shared
        let alertService = AlertService.shared

        guard let last = LastPlaylist.current else {
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
            // Attempt the add and report the real result — the now-playing track's reported service
            // isn't reliable enough to pre-gate on (a Spotify track can surface as a Sonos item).
            guard await last.add(currentTrack) else {
                alertService.showAlert(with: "Couldn’t add to \(last.title)", imageName: "exclamationmark.triangle")
                return
            }
            alertService.showAlertContent(with: currentTrack, subtitle: "Added to \(last.title)", symbolName: "plus")

            // Let tapping the toast open the playlist. Sonos resolves the real playlist for artwork;
            // streaming opens from a lightweight stub (the detail view loads it by id).
            let target: PlayableContent?
            if last.service == .library {
                target = await sonosService.sonosPlaylists().first(where: { $0.id == last.id })
            } else {
                target = last.playableContent
            }
            if let target {
                alertService.alert.handleTap = {
                    Router.main.presentedSheet = .mediaDetail(content: target, group: nil)
                }
            }
        }
    }
}

class CueSceneDelegate: NSObject, UIWindowSceneDelegate {
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
        
        // Floor only. The old 2000x1500 ceiling stopped the window growing
        // past it on a large display, and there's no reason to cap it — the
        // layout is fluid. The floor is what keeps the sidebar, content and
        // queue panel from squashing each other.
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 920, height: 600)
        
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

        if shortcutItem.type == "com.cue.search" {
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
    static let preferences = NSToolbarItem.Identifier("com.cue.preferences")
    static let sorting = NSToolbarItem.Identifier("com.cue.sorting")
//    static let newFolder = NSToolbarItem.Identifier("com.highcaffeinecontent.catalystexample.newfolder")
//    static let search = NSToolbarItem.Identifier("com.cue.search")
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


