import SonosKit
import SwiftUI

/// The screen a `RouterDestination` stands for. `withAppRouter()` renders it
/// for every value pushed onto a `NavigationStack`; a provider's collection
/// tab renders it as the tab's root, so a tab and the row that pushes the
/// same destination show the same screen.
struct RouterDestinationView: View {
    let destination: RouterDestination

    var body: some View {
        let sonosService = SonosService.shared

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
            case let .playableList(title: title, playAllItem: playAllItem, showSectionIndex: showSectionIndex, sortOptions: sortOptions, sortKey: sortKey, refreshAction: refreshAction, searchAction: searchAction, loadingStatus: loadingStatus, changeToken: changeToken, action: action):
                PlayableListView(
                    title: title,
                    playAllItem: playAllItem,
                    showSectionIndex: showSectionIndex,
                    sortOptions: sortOptions,
                    // Titles repeat across services — Plex and Subsonic
                    // both have a "Songs" — so a list with its own sort
                    // options names the key it remembers them under.
                    sortStorageKey: sortOptions.isEmpty ? nil : (sortKey ?? title),
                    refreshAction: refreshAction,
                    searchAction: searchAction,
                    loadingStatus: loadingStatus,
                    changeToken: changeToken,
                    action: action
                )
                .navigationTitle(title)
            case let .playableGridScreen(title: title, items: items, action: action):
                PlayableGridScreen(items: items, action: action)
                    .navigationTitle(title)
            case .houseHold:
                HouseholdScreen()
            case .servicePreferenceScreen:
                ServicePreferenceScreen()
            case .downloads:
                DownloadsScreen()
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
    }
}
