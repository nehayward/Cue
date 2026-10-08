import SonosKit
import SwiftUI

/// The screen a `RouterDestination` stands for. `withAppRouter()` renders it
/// for every value pushed onto a `NavigationStack`; a provider's collection
/// tab renders it as the tab's root, so a tab and the row that pushes the
/// same destination show the same screen.
struct RouterDestinationView: View {
    let destination: RouterDestination

    @Environment(\.zoomNamespace) private var zoomNamespace

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
            case let .mediaDetail(content, _, zoomSource):
                // Only a push that names its tile zooms: the same screen
                // opens from rows, search and sheets, where there is no
                // source on screen to grow out of.
                if let zoomSource, let zoomNamespace {
                    MediaDetailDestination(content: content)
                        .zoomTransition(from: zoomSource, in: zoomNamespace)
                } else {
                    MediaDetailDestination(content: content)
                }
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
            case let .playableList(title: title, playAllItem: playAllItem, showSectionIndex: showSectionIndex, allowsGrid: allowsGrid, sortOptions: sortOptions, sortKey: sortKey, refreshAction: refreshAction, searchAction: searchAction, loadingStatus: loadingStatus, changeToken: changeToken, action: action):
                PlayableListView(
                    title: title,
                    playAllItem: playAllItem,
                    showSectionIndex: showSectionIndex,
                    allowsGrid: allowsGrid,
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
            case let .downloaded(service):
                DownloadedScreen(service: service)
            case let .onDeviceCollection(collection, service):
                OnDeviceCollectionScreen(collection: collection, service: service)
            case .spotifyUserPlaylist:
                List {
                    SpotifyUsersPlaylistView(playlistCountLimit: .max, hideNavigation: true)
                        .navigationTitle("Spotify User Playlists")
                }
            case .genreList:
                GenreListView()
            case let .folderBrowse(item: item, title: title):
                if item.content.service == .plex {
                    // Plex's folders are its collections.
                    PlexCollectionScreen(collection: item)
                } else {
                    FolderBrowseView(item: item, title: title)
                }
            case let .tuneInBrowse(title: title, url: url):
                TuneInBrowseScreen(title: title, url: url)
            case .plexCollections:
                PlexCollectionsScreen()
            case .connectByIP:
                ConnectByIPScreen()
            }
        }
    }
}

/// What `.mediaDetail` opens: an album's or playlist's page, or for a Plex
/// collection (a Plex `.folder`, as in `.folderBrowse`), the collection's —
/// so a link to one, like the banner after Add to Collection, lands there.
struct MediaDetailDestination: View {
    let content: PlayableContent

    var body: some View {
        if content.content.service == .plex, content.content.type == .folder {
            PlexCollectionScreen(collection: content)
        } else {
            MediaDetailView(playableContent: content)
        }
    }
}
