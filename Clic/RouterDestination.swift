import Foundation
import SonosKit
import SwiftUI

public enum RouterDestination: Hashable, Identifiable {
    case player(groupID: String)
    case groupDestination(content: PlayableContent)
    case manageScenes

    public var id: String {
        switch self {
        case let .player(groupID):
            groupID
        case let .groupDestination(content):
            content.content.id
        case .manageScenes:
            "manageScenes"
        }
    }
}
