import SonosKit
import SwiftUI

enum SheetDestination: Identifiable {
    case settings
    case paywall
    case groupScreen(groupScreenViewModel: GroupScreenViewModel, group: GroupRoom)
    case search(group: GroupRoom? = nil, instant: Bool = false)
    case add(mediaContent: Binding<PlayableContent?>)
    case queue(group: Binding<GroupRoom>)
    case playContent(content: PlayableContent)
    case playMedia(content: MediaContent)
    case createScene
    case scenes

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
        }
    }
}
