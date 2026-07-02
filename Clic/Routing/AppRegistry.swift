import Analytics
import RevenueCatUI
import SubscriptionKit
import SonosKit
import VibesDS
import MusicSearchKit
import SwiftUI

@MainActor
extension View {
    func withSheetDestinations(sheetDestinations: Binding<SheetDestination?>, onDismiss: (() -> Void)? = nil) -> some View {
        sheet(item: sheetDestinations, onDismiss: onDismiss) { destination in
            switch destination {
            case let .newPlaylist(group, service):
                NewPlaylistView(group: group, service: service)
                    .withEnvironments()
            case let .customSleepTimer(recentTimers, onSelect):
                SleepTimerCustomView(recentTimers: recentTimers, onSelect: onSelect)
            case let .confirmDeletePlaylist(content):
                DeletePlaylistConfirmationView(content: content)
                    .withEnvironments()
            case let .addToPlaylist(content):
                AddToPlaylistSheet(content: content)
                    .presentationDragIndicator(.hidden)
                    .withEnvironments()
            default:
                Group {
                    switch destination {
                    case let .groupScreen(group):
                        GroupScreen(coordinatorID: group.coordinatorID, sheetDestination: sheetDestinations)
                            .customizeWindowSizeForMacOS15()
                    case let .settings(destination):
                        PreferenceScreen(destination: destination)
                    case .favorites:
                        let searchRouter = Router.search
                        let selectedGroupService = SelectedGroupService(group: nil)
                        SearchScreen(favorites: true)
                            .environment(searchRouter)
                            .environment(selectedGroupService)
                            .onDisappear {
                                Router.search.path.removeAll()
                                Router.search.presentedSheet = nil
                            }
                        // MARK: Add back later maybe
                        //                        .environment(Router.search)
                    case let .search(group):
                        let searchRouter = Router.search
                        let selectedGroupService = SelectedGroupService(group: group)
                        
                        SearchScreen()
                            .environment(searchRouter)
                            .environment(selectedGroupService)
                            .onDisappear {
                                Router.search.path.removeAll()
                                Router.search.presentedSheet = nil
                            }
                    case let .sceneSearchAdd(adding):
                        let searchRouter = Router.search
                        let selectedGroupService = SelectedGroupService()
                        
                        SearchScreen()
                            .environment(adding)
                            .environment(searchRouter)
                            .environment(selectedGroupService)
                            .onDisappear {
                                Router.search.path.removeAll()
                            }
                    case let .queue(group):
                        QueueScreen(group: group)
                            .presentationDetents([.medium, .large])
                    case let .playContent(content):
                        PlayerSelectionView(playableContent: content)
                    case let .playMedia(url):
                        URLPlayMediaView(url: url)
                    case let .createScene(content):
                        NavigationStack {
                            SceneBuilderScreen(contentToAdd: ContentToAdd(add: true, content: content))
                                .addDismiss {
                                    Router.main.presentedSheet = nil
                                }
                        }
                    case .scenes:
                        SceneView()
                    case let .mediaDetail(content, group):
                        @Bindable var router = Router.secondary
                        let selectedGroupService = SelectedGroupService(group: group)

                        NavigationStack(path: $router.path) {
                            MediaDetailView(playableContent: content)
                                .navigationBarTitleDisplayMode(.inline)
                                .withAppRouter()
                                .addDismiss {
                                    sheetDestinations.wrappedValue = nil
                                }
                        }
    #if !targetEnvironment(macCatalyst) && !os(visionOS)
                        .safeArea(edge: .bottom) {
                            if !MiniPlayerManger.shared.hidden {
                                MiniPlayerView()
                                    .geometryGroup()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
    #endif
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        .environment(router)
                        .environment(selectedGroupService)
                        .customizeWindowSizeForMacOS15()
                        .withAlert()
                    case let .artistDetail(content, group):
                        let router = Router.secondary
                        let selectedGroupService = SelectedGroupService(group: group)
                        
                        NavigationStack {
                            ArtistDetailView(playableContent: content)
                                .navigationBarTitleDisplayMode(.inline)
                                .withAppRouter()
                                .addDismiss {
                                    sheetDestinations.wrappedValue = nil
                                }
                        }
                        .miniPlayerOnScrollHandler()
    #if !targetEnvironment(macCatalyst) && !os(visionOS)
                        .safeArea(edge: .bottom) {
                            MiniPlayerView()
                        }
    #endif
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        .environment(router)
                        .environment(selectedGroupService)
                        .customizeWindowSizeForMacOS15()
                        .withAlert()
                        
                    case let .searchAdd(adding):
                        let searchRouter = Router.search
                        let selectedGroupService = SelectedGroupService()

                        SearchScreen(isAlarmSearch: true)
                            .environment(adding)
                            .environment(searchRouter)
                            .environment(selectedGroupService)
                    case let .alarms(group):
                        NavigationStack {
                            AlarmListView(group: group)
                                .withAppRouter()
                                .addDismiss {
                                    Router.main.presentedSheet = nil
                                }
                        }
                    case .customSleepTimer:
                        // Handled above, before the shared sheet chrome.
                        EmptyView()
                    case let .browse(group: group):
                        let selectedGroupService = SelectedGroupService(group: group)
                        BrowseScreen()
                            .environment(selectedGroupService)
                    case .newPlaylist:
                        EmptyView()
                    case .confirmDeletePlaylist:
                        EmptyView()
                    case .addToPlaylist:
                        EmptyView()
                    case let .renamePlaylist(content: content):
                        NewPlaylistView(playlist: content)
                    case let .speakerSettings(room: room):
                        NavigationStack {
                            SpeakerSettingsView(room: room)
                        }
                        .presentationDetents([.medium, .large])
                    case let .selectGroup(selectedGroupService: selectedGroupService, onSelection: onSelection, onQueueSelection: onQueueSelection, defaultPosition: defaultPosition, content: content):
                        SelectGroupView(content: content, defaultPosition: defaultPosition, onSelection: onSelection, onQueueSelection: onQueueSelection)
                            .presentationDetents([.fraction(0.8), .large])
                            .environment(selectedGroupService)
                    case .plexManagement:
                        PlexManagementView()
                    case let .volumeControlsScreen(groupID: groupID):
                        VolumeControlsScreen(groupID: groupID)
                    case .newsletter:
                        NewsletterSignupScreen()
                    case .spotifyUserPlaylists:
                        SpotifyPlaylistScreen()
                    case let .editScene(scene):
                        NavigationStack {
                            SceneBuilderScreen(edit: true, scene: scene)
                                .addDismiss {
                                    Router.main.presentedSheet = nil
                                }
                        }
                    case .reorderAppleLibrarySections:
                        ReorderAppleLibrarySectionsView()
                    case .reorderSpotifyLibrarySections:
                        ReorderSpotifyLibrarySectionsView()
                    case .reorderSoundCloudLibrarySections:
                        ReorderSoundCloudLibrarySectionsView()
                    case .shareToWatch:
                        ShareToWatchView()
                    case .paywall, .onboard:
                        // Routed via `withFullScreenCoverDestinations` —
                        // listed here to keep the switch exhaustive but never
                        // reached because the sheet binding doesn't fire for
                        // these destinations in practice.
                        EmptyView()
                    }
                }
                .withEnvironments()
                .presentationSizingiOS18()
                .frame(idealWidth: 600, idealHeight: 800)
                #if targetEnvironment(macCatalyst)
                .presentationDragIndicator(.hidden)
                #endif
            }
        }
    }
    
    /// FullScreenCover variant of `withSheetDestinations`. Used for paywall +
    /// onboarding, where we want full canvas, no swipe-to-dismiss, and a
    /// "this is a moment" presentation. Route via `router.presentedFullScreenCover`
    /// (or `router.fullScreenCover(to:)`) instead of `presentedSheet`.
    ///
    /// On native macOS `fullScreenCover` isn't available, so this is a no-op —
    /// destinations that need to surface on native macOS should also live in
    /// `withSheetDestinations` or `withPopoverDestinations`. (Currently every
    /// shipping target uses Mac Catalyst, so this branch is in practice
    /// always live.)
    func withFullScreenCoverDestinations(destinations: Binding<SheetDestination?>, onDismiss: (() -> Void)? = nil) -> some View {
        #if !os(macOS)
        return fullScreenCover(item: destinations, onDismiss: onDismiss) { destination in
            switch destination {
            case .paywall:
                ClicPaywall()
                    .withEnvironments()
            case .onboard:
                WelcomeScreen()
                    .withEnvironments()
            default:
                EmptyView()
            }
        }
        #else
        return self
        #endif
    }

    func withPopoverDestinations(popoverDestination: Binding<SheetDestination?>) -> some View {
        popover(item: popoverDestination) { destination in
            Group {
                switch destination {
                case let .groupScreen(group):
                    GroupScreen(coordinatorID: group.coordinatorID, sheetDestination: popoverDestination)
                        .frame(idealWidth: 400, idealHeight: 800)
                case .paywall:
                    ClicPaywall()
                case .settings:
                    PreferenceScreen()
                case let .search(group):
                    let searchRouter = Router.search
                    let selectedGroupService = SelectedGroupService(group: group)
                    SearchScreen()
                        .environment(searchRouter)
                        .environment(selectedGroupService)
                        .onDisappear {
                            Router.search.path.removeAll()
                        }
                case let .sceneSearchAdd(adding):
                    let searchRouter = Router.search
                    let selectedGroupService = SelectedGroupService()
                    
                    SearchScreen()
                        .environment(adding)
                        .environment(searchRouter)
                        .environment(selectedGroupService)
                        .onDisappear {
                            Router.search.path.removeAll()
                        }
                case let .queue(group):
                    let selectedGroupService = SelectedGroupService(group: group)
                    QueueScreen(group: group)
                        .presentationDetents([.medium, .large])
                        .environment(selectedGroupService)
                case let .playContent(content):
                    PlayerSelectionView(playableContent: content)
                case let .playMedia(url):
                    URLPlayMediaView(url: url)
                case let .createScene(content):
                    NavigationStack {
                        SceneBuilderScreen(contentToAdd: ContentToAdd(add: true, content: content))
                    }
                case .scenes:
                    SceneView()
                case let .mediaDetail(content, group):
                    let router = Router()
                    let selectedGroupService = SelectedGroupService(group: group)
                    
                    NavigationStack {
                        MediaDetailView(playableContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .withAppRouter()
                    }
                    .scrollContentBackground(.hidden)
                    .environment(router)
                    .environment(selectedGroupService)
                    
                case let .artistDetail(content, group):
                    @Bindable var router = Router()
                    let selectedGroupService = SelectedGroupService(group: group)
                    
                    NavigationStack(path: $router.path) {
                        ArtistDetailView(playableContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .withAppRouter()
                            .withAlert()
                    }
                    .scrollContentBackground(.hidden)
                    .safeArea(edge: .bottom) {
                        MiniPlayerView()
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .environment(router)
                    .environment(selectedGroupService)
                case let .searchAdd(adding):
                    let router = Router()
                    let selectedGroupService = SelectedGroupService()
                    
                    SearchScreen(isAlarmSearch: true)
                        .environment(adding)
                        .environment(router)
                        .environment(selectedGroupService)
                case .alarms:
                    NavigationStack {
                        AlarmListView()
                            .withAppRouter()
                            .addDismiss {
                                Router.main.presentedSheet = nil
                            }
                    }
                case let .customSleepTimer(recentTimers, onSelect):
                    SleepTimerCustomView(recentTimers: recentTimers, onSelect: onSelect)
                case let .browse(group: group):
                    let selectedGroupService = SelectedGroupService(group: group)
                    BrowseScreen()
                        .environment(selectedGroupService)
                case let .newPlaylist(group, service):
                    NewPlaylistView(group: group, service: service)
                case let .renamePlaylist(content: content):
                    NewPlaylistView(playlist: content)
                case let .volumeControlsScreen(groupID: groupID):
                    VolumeControlsScreen(groupID: groupID)
                        .frame(idealWidth: 400)
                        .presentationCompactAdaptation(.popover)
                case .onboard:
                    WelcomeScreen()
                case .newsletter:
                    NewsletterSignupScreen()
                default:
                    EmptyView()
                }
            }
            .withEnvironments()
        }
    }
    
    func withAppRouter() -> some View {
        @Bindable var sonosService = SonosService.shared
        
        return navigationDestination(for: RouterDestination.self) { destination in
            Group {
                switch destination {
                case let .player(groupID):
                    if sonosService.groups.contains(where: { $0.coordinatorID == groupID }) {
                        LargePlayerView(coordinatorID: groupID)
                    } else {
                        GroupNoLongerAvailableScreen()
                    }
                case let .groupDestination(content, position):
                    PlayerSelectionView(playableContent: content, position: position)
                case .manageScenes:
                    ManageSceneScreen()
                case let .mediaDetail(content, _):
                    MediaDetailView(playableContent: content)
                case let .artistDetail(content, _):
                    ArtistDetailView(playableContent: content)
                case let .createScene(content):
                    NavigationStack {
                        SceneBuilderScreen(contentToAdd: ContentToAdd(add: true, content: content))
                    }
                case .alarms:
                    AlarmListView()
                case let .addAlarm(group):
                    AlarmView(group: group, alarm: .newAlarm)
                case let .editAlarm(alarm):
                    AlarmView(edit: true, alarm: alarm)
                case .speakerSettingsList:
                    SpeakerSettingsListView()
                case let .speakerSettings(room: room):
                    SpeakerSettingsView(room: room)
                case let .playableContentList(group: group, contentType: contentType):
                    let title = switch contentType {
                    case .track:
                        "Songs"
                    case .album:
                        "Albums"
                    case .artist:
                        "Artists"
                    case .playlist:
                        "Playlists"
                    default:
                        ""
                    }
                    PlayableContentList(type: contentType)
                        .navigationTitle(title)
                        .environment(group)
                case .fullPlayHistoryList:
                    PlayHistoryFullView()
                case let .playableLibraryList(title: title, items: items, action: action):
                    PlayableList(items: items, action: action)
                        .navigationTitle(title)
                case let .playableList(title: title, playAllItem: playAllItem, showSectionIndex: showSectionIndex, action: action):
                    PlayableListView(playAllItem: playAllItem, showSectionIndex: showSectionIndex, action: action)
                        .navigationTitle(title)
                case let .playableGridScreen(title: title, items: items, action: action):
                    PlayableGridScreen(items: items, action: action)
                        .navigationTitle(title)
                case .houseHold:
                    HouseholdScreen()
                case .servicePreferenceScreen:
                    ServicePreferenceScreen()
                case .spotifyUserPlaylist:
                    List {
                        SpotifyUsersPlaylistView(playlistCountLimit: .max, hideNavigation: true)
                            .navigationTitle("Spotify User Playlists")
                    }
                case .genreList:
                    GenreListView()
                case let .folderBrowse(item: item, title: title):
                    FolderBrowseView(item: item, title: title)
                case .connectByIP:
                    ConnectByIPScreen()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    func withInspector(inspectorDestination: Binding<InspectorDestination?>) -> some View {
#if !os(visionOS)
        modifier(InspectorDestinationModifier(destination: inspectorDestination))
#else
        self
#endif
    }
    
    func withEnvironments() -> some View {
        environment(SonosService.shared)
            .environment(SubscriptionService.shared)
            .environment(AlertService.shared)
            .environment(MusicSearchService.shared)
            .environment(PlaylistContainer.shared)
            .environment(PlayHistoryService.shared)
            .environment(AppleMusicBrowseService.shared)
            .environment(SpotifyBrowseService.shared)
            .environment(SoundCloudBrowseService.shared)
            .environment(DeezerBrowseService.shared)
            .environment(PlexBrowseService.shared)
            .environment(LibraryBrowseService.shared)
            .environment(MiniPlayerManger.shared)
            .environment(CoreFeatures.shared)
            .environment(RemoteFeatureFlags.shared)
    }
    
    @ViewBuilder
    func addDismiss(override: Bool = false, action: @escaping () -> Void) -> some View {
        if override || Router.main.presentedSheet != nil  {
            toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        action()
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
        } else {
            self
        }
    }
    
    func sheetRequirements() -> some View {
        withEnvironments()
        .presentationSizingiOS18()
        .frame(idealWidth: 600, idealHeight: 800)
    }
}

#if !os(visionOS)
private struct InspectorDestinationModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var destination: InspectorDestination?

    func body(content: Content) -> some View {
        content.inspector(isPresented: Binding(
            get: { destination != nil },
            set: { isPresented in
                // Honor a system-initiated dismissal only in compact width,
                // where the inspector presents as a sheet the user can drag
                // away. In regular width it's a column with no dismiss
                // gesture — a `false` there is presentation churn (a window
                // still too narrow while launching, other presentations
                // settling) and latching it closes the inspector right after
                // it opens.
                if !isPresented, horizontalSizeClass == .compact {
                    destination = nil
                }
            }
        )) {
            // A dedicated view rather than inline content: the inspector
            // hosts its content in its own column/sheet and doesn't reliably
            // re-invoke this closure when the destination is reassigned —
            // e.g. .queue(oldGroup) → .queue(newGroup) when the selected
            // group changes — which left the queue showing the previous
            // group. A view whose own body reads the binding registers the
            // Observation dependency on the hosted view itself, so it
            // updates in place.
            InspectorContentView(destination: $destination)
        }
    }
}

private struct InspectorContentView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router
    @Binding var destination: InspectorDestination?

    /// The destination enum captures the group at the moment the inspector
    /// was opened, but the inspector is meant to track the *selected* group.
    /// Resolve it live here (reads registered on this view's body), instead
    /// of relying on ClicApp's selectedID onChange to reassign the enum.
    private func currentGroup(_ fallback: GroupRoom?) -> GroupRoom? {
        if let id = router.selectedID,
           let live = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
            return live
        }
        return fallback
    }

    var body: some View {
        VStack {
            switch destination {
            case let .search(group):
                // Router.search, matching the sheet registry. SearchScreen
                // reads Router from the environment and attaches its own
                // sheet host to `router.presentedSheet`; without this it
                // inherits Router.main, whose presentedSheet the app-level
                // host already binds. Two hosts on one binding: whichever
                // loses the presentation race writes nil back and
                // dismisses the sheet that just appeared.
                SearchScreen {
                    destination = nil
                }
                .environment(Router.search)
                .environment(SelectedGroupService(group: currentGroup(group)))
                .onDisappear {
                    Router.search.path.removeAll()
                    Router.search.presentedSheet = nil
                }
            case let .queue(group):
                let current = currentGroup(group) ?? group
                QueueScreen(group: current) {
                    destination = nil
                }
                // Remount per group: QueueScreen's loading is appear-driven
                // (selectedGroupService sync, playMode fetch, queue/scroll
                // state in @State), so a param-only group change leaves the
                // previous group's queue on screen. Keyed by coordinatorID,
                // so topology refreshes that replace the GroupRoom instance
                // don't reset it.
                .id(current.coordinatorID)
            case let .browse(group):
                BrowseScreen {
                    destination = nil
                }
                .environment(SelectedGroupService(group: currentGroup(group)))
            default:
                EmptyView()
                    .onAppear {
                        destination = nil
                    }
            }
        }
        .withEnvironments()
#if targetEnvironment(macCatalyst)
        .inspectorColumnWidth(min: 360, ideal: 450, max: 450)
#else
        .inspectorColumnWidth(min: 260, ideal: 360, max: 500)
        .presentationBackgroundInteraction(.disabled)
#endif
    }
}
#endif
