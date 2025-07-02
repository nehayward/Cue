import SonosKit
import SwiftUI

enum InspectorDestination: Identifiable, Equatable {
    case settings
    case groupScreen(group: GroupRoom)
    case search(group: GroupRoom? = nil)
    case queue(group: GroupRoom)
    case paywall
    case sceneSearchAdd(adding: ContentToAdd)
    case playContent(content: PlayableContent)
    case playMedia(content: MediaContent)
    case mediaDetail(content: PlayableContent, group: GroupRoom?)
    case artistDetail(content: PlayableContent, group: GroupRoom?)
    case browse(group: GroupRoom? = nil)
    case createScene
    case scenes
    case searchAdd(adding: ContentToAdd)
    case alarms(group: GroupRoom? = nil)
    case customSleepTimer(group: GroupRoom)

    var id: String {
        switch self {
        case .browse:
            "browse"
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
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
