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
                    SearchScreen(group: group)
                        .environment(Router())
                        .environment(SelectedGroupService(group: group))
                    // MARK: Add back later maybe
//                        .environment(Router.search)
                case let .sceneSearchAdd(adding):
                    SearchScreen()
                        .environment(Router())
                        .environment(adding)
                        .environment(SelectedGroupService())
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
                case let .createScene(content):
                    NavigationStack {
                        SceneBuilderScreen(sheetDestination: .constant(nil), playableContent: content)
                    }
                case .scenes:
                    SceneView()
                case let .mediaDetail(content, group):
                    NavigationStack {
                        MediaDetailView(playableContent: content)
                            .navigationBarTitleDisplayMode(.inline)
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
                    .environment(Router())
                    .environment(SelectedGroupService(group: group))
                case let .artistDetail(content, group):
                    @State var router = Router()
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
                    .environment(SelectedGroupService(group: group))
                case let .searchAdd(adding):
                    SearchScreen()
                        .environment(Router())
                        .environment(adding)
                        .environment(SelectedGroupService())
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
                    BrowseScreen()
                        .environment(SelectedGroupService(group: group))
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
                case let .selectGroup(selectedGroupService: selectedGroupService):
                    SelectGroupView()
                        .presentationDetents([.medium, .large])
                        .presentationBackground(.thinMaterial)
                        .presentationCornerRadius(24)
                        .environment(selectedGroupService)
                }
            }
            .withEnvironments()
        }
    }

    func withPopoverDestinations(popoverDestination: Binding<SheetDestination?>)  -> some View {
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
                    SearchScreen(group: group)
                        .environment(Router())
                        .environment(SelectedGroupService(group: group))
                case let .sceneSearchAdd(adding):
                    SearchScreen()
                        .environment(Router())
                        .environment(adding)
                        .environment(SelectedGroupService())
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
                case let .createScene(content):
                    NavigationStack {
                        SceneBuilderScreen(sheetDestination: .constant(nil), playableContent: content)
                    }
                case .scenes:
                    SceneView()
                case let .mediaDetail(content, group):
                    NavigationStack {
                        MediaDetailView(playableContent: content)
                            .environment(group)
                            .environment(Router())
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .scrollContentBackground(.hidden)
                    .presentationBackground(.thinMaterial)
                case let .artistDetail(content, group):
                    @State var router = Router()
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
                    .environment(SelectedGroupService(group: group))
                case let .searchAdd(adding):
                    SearchScreen()
                        .environment(adding)
                        .environment(Router())
                        .environment(SelectedGroupService())
                case .alarms:
                    NavigationStack {
                        AlarmListView()
                    }
                case let .customSleepTimer(group):
                    SleepTimerCustomView(group: group)
                case let .browse(group: group):
                    BrowseScreen()
                        .environment(SelectedGroupService(group: group))
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
            case let .mediaDetail(content, group):
                MediaDetailView(playableContent: content)
                    .environment(group)
            case let .artistDetail(content, group):
                ArtistDetailView(playableContent: content)
                    .environment(SelectedGroupService(group: group))
            case let .createScene(content):
                SceneBuilderScreen(sheetDestination: .constant(nil), playableContent: content)
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
            }
        }
    }

    func withInspector(inspectorDestination: Binding<InspectorDestination?>) -> some View {
        #if !os(visionOS)
        inspector(isPresented: .constant(inspectorDestination.wrappedValue  != nil)) {
            Group {
                switch inspectorDestination.wrappedValue {
                case let .search(group):
                    SearchScreen(group: group)
                    #if targetEnvironment(macCatalyst)
                        .inspectorColumnWidth(500)
                    #else
                        .inspectorColumnWidth(400)
                    #endif
                        .environment(SelectedGroupService(group: group))
                case let .queue(group):
                    QueueScreen(group: group)
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
    }

    @ViewBuilder
    func addDismiss(override: Bool = false, action: @escaping () -> Void) -> some View {
        if override || [.mac, .vision, .pad].contains(UIDevice.current.userInterfaceIdiom)  {
            toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark.circle.fill", role: .cancel, action: action)
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        } else {
            self
        }
    }
}
