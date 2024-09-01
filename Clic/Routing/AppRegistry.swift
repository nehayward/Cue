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
            Group {
                switch destination {
                case let .groupScreen(group):
                    GroupScreen(coordinatorID: group.coordinatorID, sheetDestination: sheetDestinations)
                case .paywall:
                   ClicPaywall()
//                    PaywallView(displayCloseButton: true)
//                        .onPurchaseCompleted { transaction, customerInfo in
//                                ///                     print("Purchase completed: \(customerInfo.entitlements)")
//                                ///                     self.displayPaywall = false
//                                ///                 }
//                            ///                 print(
//                            print("Complete")
//                        }
//                        .onAppear {
//                            Analytics.shared.track(.viewedPaywall)
//                        }
                case .settings:
                    PreferenceScreen()
                case let .search(group):
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService(group: group)

                    SearchScreen()
                        .environment(router)
                        .environment(selectedGroupService)
                    // MARK: Add back later maybe
//                        .environment(Router.search)
                case let .sceneSearchAdd(adding):
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService()

                    SearchScreen()
                        .environment(adding)
                        .environment(router)
                        .environment(selectedGroupService)
                case let .queue(group):
                    QueueScreen(group: group)
                        .presentationDetents([.medium, .large])
                case let .playContent(content):
                    PlayerSelectionView(playableContent: content)
                case let .playMedia(url):
                    NavigationStack {
                        PlayerSelectionView(urlScheme: url)
                            .navigationBarTitleDisplayMode(.inline)
                            .navigationTitle("Choose Group")
                    }
                case .createScene:
                    NavigationStack {
                        SceneBuilderScreen()
                    }
                case .scenes:
                    SceneView()
                case let .mediaDetail(content, group):
                    @State var selectedGroupService = SelectedGroupService(group: group)
                    @State var router = Router()

                    NavigationStack {
                        MediaDetailView(playableContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .withAppRouter(router: router)
                            .addDismiss {
                                sheetDestinations.wrappedValue = nil
                            }
                    }
                    .scrollContentBackground(.hidden)
                    .presentationBackground(.thinMaterial)
                    .safeAreaInset(edge: .bottom) {
                        MiniPlayerView()
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .environment(router)
                    .environment(selectedGroupService)
                case let .artistDetail(content, group):
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService(group: group)

                    NavigationStack {
                        ArtistDetailView(playableContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .withAppRouter(router: router)
                            .addDismiss {
                                sheetDestinations.wrappedValue = nil
                            }
                    }
                    .scrollContentBackground(.hidden)
                    .presentationBackground(.thinMaterial)
                    .safeAreaInset(edge: .bottom) {
                        MiniPlayerView()
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .environment(router)
                    .environment(selectedGroupService)

                case let .searchAdd(adding):
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService()

                    SearchScreen(isAlarmSearch: true)
                        .environment(adding)
                        .environment(router)
                        .environment(selectedGroupService)
                case let .alarms(group):
                    Group {
                        @State var router = Router()
                        NavigationStack {
                            AlarmListView(group: group)
                                .withAppRouter(router: router)
                        }
                    }
                case let .customSleepTimer(group):
                    SleepTimerCustomView(group: group)
                case let .browse(group: group):
                    @State var selectedGroupService = SelectedGroupService(group: group)
                    BrowseScreen()
                        .environment(selectedGroupService)
                case let .newPlaylist(group: group):
                    NewPlaylistView(group: group)
                case let .renamePlaylist(content: content):
                    NewPlaylistView(playlist: content)
                case let .speakerSettings(room: room):
                    NavigationStack {
                        SpeakerSettingsView(room: room)
                    }
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.thinMaterial)
                    .presentationCornerRadius(24)
                case let .selectGroup(selectedGroupService: selectedGroupService, onSelection: onSelection):
                    SelectGroupView(onSelection: onSelection)
                        .presentationDetents([.medium, .large])
                        .presentationBackground(.thinMaterial)
                        .presentationCornerRadius(24)
                        .environment(selectedGroupService)
                case .plexManagement:
                    PlexManagementView()
                }
            }
            .withEnvironments()
            .frame(idealWidth: 800, idealHeight: 800)
        }
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
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService(group: group)

                    SearchScreen()
                        .environment(router)
                        .environment(selectedGroupService)
                case let .sceneSearchAdd(adding):
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService()

                    SearchScreen()
                        .environment(adding)
                        .environment(router)
                        .environment(selectedGroupService)
                case let .queue(group):
                    @State var selectedGroupService = SelectedGroupService(group: group.wrappedValue)

                    QueueScreen(group: group)
                        .presentationDetents([.medium, .large])
                        .environment(selectedGroupService)
                case let .playContent(content):
                    PlayerSelectionView(playableContent: content)
                case let .playMedia(url):
                    NavigationStack {
                        PlayerSelectionView(urlScheme: url)
                            .navigationBarTitleDisplayMode(.inline)
                            .navigationTitle("Choose Group")
                    }
                case .createScene:
                    NavigationStack {
                        SceneBuilderScreen()
                    }
                case .scenes:
                    SceneView()
                case let .mediaDetail(content, group):
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService(group: group)

                    NavigationStack {
                        MediaDetailView(playableContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .withAppRouter(router: router)
                    }
                    .scrollContentBackground(.hidden)
                    .presentationBackground(.thinMaterial)
                    .environment(router)
                    .environment(selectedGroupService)

                case let .artistDetail(content, group):
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService(group: group)

                    NavigationStack(path: $router.path) {
                        ArtistDetailView(playableContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .withAppRouter(router: router)
                    }
                    .scrollContentBackground(.hidden)
                    .presentationBackground(.thinMaterial)
                    .safeAreaInset(edge: .bottom) {
                        MiniPlayerView()
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .environment(router)
                    .environment(selectedGroupService)
                case let .searchAdd(adding):
                    @State var router = Router()
                    @State var selectedGroupService = SelectedGroupService()

                    SearchScreen(isAlarmSearch: true)
                        .environment(adding)
                        .environment(router)
                        .environment(selectedGroupService)
                case .alarms:
                    NavigationStack {
                        AlarmListView()
                    }
                case let .customSleepTimer(group):
                    SleepTimerCustomView(group: group)
                case let .browse(group: group):
                    @State var selectedGroupService = SelectedGroupService(group: group)
                    BrowseScreen()
                        .environment(selectedGroupService)
                case let .newPlaylist(group: group):
                    NewPlaylistView(group: group)
                case let .renamePlaylist(content: content):
                    NewPlaylistView(playlist: content)
                default:
                    EmptyView()
                }
            }
            .withEnvironments()
        }
    }

    func withAppRouter(router: Router) -> some View {
        @Bindable var sonosService = SonosService.shared

        return navigationDestination(for: RouterDestination.self) { destination in
            switch destination {
            case let .player(groupID):
                if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                    LargePlayerView(group: $sonosService.sorted[group])
                } else {
                    Text("Group No Longer Available")
                        .onTapGesture {
                            router.path.removeAll()
                        }
                }
            case let .groupDestination(content, position):
                PlayerSelectionView(playableContent: content, position: position)
            case .manageScenes:
                ManageSceneScreen()
            case let .mediaDetail(content, _):
                MediaDetailView(playableContent: content)
            case let .artistDetail(content, _):
                ArtistDetailView(playableContent: content)
            case .createScene:
                SceneBuilderScreen()
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
            case let .playableGridScreen(title: title, items: items, action: action):
                PlayableGridScreen(items: items, action: action)
                    .navigationTitle(title)
            case .houseHold:
                HouseholdScreen()
            }
        }
    }

    func withInspector(inspectorDestination: Binding<InspectorDestination?>) -> some View {
#if !os(visionOS)
        inspector(isPresented: .constant(inspectorDestination.wrappedValue != nil)) {
            Group {
                switch inspectorDestination.wrappedValue {
                case let .search(group):
                    SearchScreen {
                        inspectorDestination.wrappedValue = nil
                    }
#if targetEnvironment(macCatalyst)
                    .inspectorColumnWidth(500)
#else
                    .inspectorColumnWidth(400)
#endif
                    .environment(SelectedGroupService(group: group))
                case let .queue(group):
                    QueueScreen(closeInspector: {
                        inspectorDestination.wrappedValue = nil
                    }, group: group)
#if targetEnvironment(macCatalyst)
                    .inspectorColumnWidth(500)
#else
                    .inspectorColumnWidth(400)
#endif
                case let .browse(group):
                    @State var selectedGroupService = SelectedGroupService(group: group)
                    BrowseScreen {
                        inspectorDestination.wrappedValue = nil
                    }
                    .environment(selectedGroupService)
#if targetEnvironment(macCatalyst)
                    .inspectorColumnWidth(500)
#else
                    .inspectorColumnWidth(400)
#endif
                default:
                    EmptyView()
                        .onAppear {
                            inspectorDestination.wrappedValue = nil
                        }
                }
            }
            .withEnvironments()
        }
#else
        return self
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
            .environment(PlexBrowseService.shared)
            .environment(LibraryBrowseService.shared)
    }

    @ViewBuilder
    func addDismiss(override: Bool = false, action: @escaping () -> Void) -> some View {
        if override || [.mac, .vision, .pad].contains(UIDevice.current.userInterfaceIdiom)  {
            toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark.circle.fill", role: .cancel, action: action)
                        .tint(.primary)
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        } else {
            self
        }
    }
}
