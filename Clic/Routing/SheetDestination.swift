import SonosKit
import SwiftUI

enum SheetDestination: Identifiable, Equatable {
    case settings
    case paywall
    case groupScreen(group: GroupRoom)
    case search(group: GroupRoom? = nil)
    case sceneSearchAdd(adding: ContentToAdd)
    case queue(group: Binding<GroupRoom>)
    case playContent(content: PlayableContent)
    case playMedia(content: MediaContent)
    case mediaDetail(content: PlayableContent, group: GroupRoom?)
    case artistDetail(content: PlayableContent, group: GroupRoom?)
    case createScene(content: PlayableContent? = nil)
    case scenes
    case searchAdd(adding: ContentToAdd)
    case alarms(group: GroupRoom? = nil)
    case customSleepTimer(group: GroupRoom)
    case browse(group: GroupRoom? = nil)
    case newPlaylist(group: GroupRoom? = nil)
    case renamePlaylist(content: PlayableContent)

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
        }
    }

    static func == (lhs: SheetDestination, rhs: SheetDestination) -> Bool {
        lhs.id == rhs.id
    }
}
