import SonosKit
import SwiftUI

enum SheetDestination: Identifiable, Equatable {
    case settings(destination: RouterDestination? = nil)
    case queue(group: GroupRoom)
    case search(group: GroupRoom? = nil)
    case groupScreen(group: GroupRoom)
    case paywall
    case favorites
    case sceneSearchAdd(adding: ContentToAdd)
    case playContent(content: PlayableContent)
    case playMedia(url: URL)
    case mediaDetail(content: PlayableContent, group: GroupRoom?)
    case artistDetail(content: PlayableContent, group: GroupRoom?)
    case createScene(content: PlayableContent?)
    case editScene(SonosScene)
    case scenes
    case searchAdd(adding: ContentToAdd)
    case alarms(group: GroupRoom? = nil)
    case customSleepTimer(recentTimers: Storage<Duration>, onSelect: (Duration) async -> Void)
    case browse(group: GroupRoom? = nil)
    case newPlaylist(group: GroupRoom? = nil, service: MusicService = .library)
    case renamePlaylist(content: PlayableContent)
    case confirmDeletePlaylist(content: PlayableContent)
    case addToPlaylist(content: PlayableContent)
    case speakerSettings(room: Room)
    case selectGroup(selectedGroupService: SelectedGroupService, onSelection: ((GroupRoom) async throws -> Void)? = nil, onQueueSelection: ((GroupRoom, QueuePosition) async throws -> Void)? = nil, defaultPosition: QueuePosition = .now, content: PlayableContent? = nil)
    case plexManagement
    case subsonicManagement
    case volumeControlsScreen(groupID: String)
    case onboard
    case newsletter
    case spotifyUserPlaylists
    case reorderAppleLibrarySections
    case reorderSpotifyLibrarySections
    case reorderSoundCloudLibrarySections
    case shareToWatch
    /// Which providers get a tab of their own (a sidebar section on iPad
    /// and Mac), and in what order.
    case customizeTabs

    var id: String {
        switch self {
        case .settings:
            "settings"
        case .paywall:
            "paywall"
        case .groupScreen:
            "groupScreen"
        case .search:
            "search"
        case .sceneSearchAdd:
            "sceneSearchAdd"
        case .queue:
            "queue"
        case .playContent:
            "playContent"
        case let .playMedia(content):
            "mediaContent.\(content)"
        case .createScene:
            "createScene"
        case .scenes:
            "scenes"
        case let .mediaDetail(content, _):
            content.id + "media"
        case let .artistDetail(content, _):
            content.id + "artist"
        case .searchAdd:
            "searchAdd"
        case .alarms:
            "alarms"
        case .customSleepTimer:
            "customSleepTimer"
        case .browse:
            "browse"
        case .newPlaylist:
            "new.playlist"
        case .renamePlaylist:
            "rename.playlist"
        case let .confirmDeletePlaylist(content):
            content.id + "confirmDelete"
        case let .addToPlaylist(content):
            content.id + "addToPlaylist"
        case .speakerSettings:
            "speaker.configuration"
        case .selectGroup:
            "selectGroup"
        case .plexManagement:
            "plexManagement"
        case .subsonicManagement:
            "subsonicManagement"
        case .volumeControlsScreen:
            "volumeControlsScreen"
        case .favorites:
            "favorites"
        case .shareToWatch:
            "shareToWatch"
        default:
            "\(self)"
        }
    }

    static func == (lhs: SheetDestination, rhs: SheetDestination) -> Bool {
        lhs.id == rhs.id
    }
}
