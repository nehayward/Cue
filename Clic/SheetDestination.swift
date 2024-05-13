import SonosKit
import SwiftUI

enum SheetDestination: Identifiable, Equatable {
    case settings
    case paywall
    case groupScreen(group: GroupRoom)
    case search(group: GroupRoom? = nil, instant: Bool = false)
    case add(mediaContent: Binding<PlayableContent?>)
    case queue(group: Binding<GroupRoom>)
    case playContent(content: PlayableContent)
    case playMedia(content: MediaContent)
    case mediaDetail(content: PlayableContent, group: GroupRoom?)
    case artistDetail(content: PlayableContent, group: GroupRoom?)
    case createScene(content: PlayableContent? = nil)
    case scenes
    case searchAdd(adding: ContentToAdd)
    case alarms(group: GroupRoom? = nil)

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
        case .add:
            "media"
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
        }
    }

    static func == (lhs: SheetDestination, rhs: SheetDestination) -> Bool {
        lhs.id == rhs.id
    }
}
