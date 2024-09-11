import Analytics
import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults
import TipKit
import AuthenticationServices

struct PlexBrowseScreen: View {
    @Environment(\.dismiss) var dismiss

    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(PlexBrowseService.self) private var plexBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router = Router()

    var body: some View {
        @Bindable var plexBrowseService = plexBrowseService
        @Bindable var sonosService = sonosService

        NavigationStack(path: $router.path) {
            ScrollView {
                PlexAuthorizationFlowView()
                VStack(alignment: .leading) {
                    if musicSearchService.isPlexAuthorized, musicSearchService.plexServerID != nil {
                        Section {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                                ForEach(plexBrowseService.userPlaylists.prefix(4)) { item in
                                    PlayableCardView(item: item)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Playlists (\(plexBrowseService.userPlaylists.count))")
                                Spacer()
                                NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlists", items: $plexBrowseService.userPlaylists, action: { offset in
                                    await plexBrowseService.updateUserPlaylists(offset: offset)
                                })) {
                                    Text("Show all \(Image(systemName: "chevron.right"))")
                                }
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical)
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Plex Library")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: musicSearchService.plexServerID) {
                await updatePlexBrowseService()
            }
            // MARK: Workaround into I can use extension on view iOS 18 bug
            .navigationDestination(for: RouterDestination.self) { destination in
                switch destination {
                case let .player(groupID):
                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                        LargePlayerView(group: $sonosService.sorted[group])
                    } else {
                        Text("Group No Longer Available")
                            .onTapGesture {
                                dismiss()
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
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                await updatePlexBrowseService()
            }
        }
    }

    @MainActor
    private func updatePlexBrowseService() async {
        await plexBrowseService.updateUserPlaylists()
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

