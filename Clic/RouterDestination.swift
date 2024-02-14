import Foundation
import MusicSearchKit
import SonosKit
import SwiftUI

public enum RouterDestination: Hashable, Identifiable {
    case player(groupID: String)
    case groupDestination(content: PlayableContent)
    case manageScenes
    case mediaDetail(id: String, title: String, kind: MediaKind, group: GroupRoom?)

    public var id: String {
        switch self {
        case let .player(groupID):
            groupID
        case let .groupDestination(content):
            content.content.id
        case .manageScenes:
            "manageScenes"
        case let .mediaDetail(id, title, kind, _):
            id + title + kind.rawValue
        }
    }
}
