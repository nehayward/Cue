import Foundation
import MusicSearchKit
import SonosKit
import SwiftUI

public enum RouterDestination: Hashable, Identifiable {
    case player(groupID: String)
    case groupDestination(content: PlayableContent, position: QueuePosition = .now)
    case manageScenes
    case createScene(content: PlayableContent? = nil)
    case mediaDetail(content: PlayableContent, group: GroupRoom?)
    case artistDetail(content: PlayableContent, group: GroupRoom?)
    case alarms
    case addAlarm(group: GroupRoom? = nil)
    case editAlarm(alarm: Alarm)

    public var id: String {
        switch self {
        case let .player(groupID):
            groupID
        case let .groupDestination(content, _):
            content.content.id
        case .manageScenes:
            "manageScenes"
        case let .mediaDetail(content, _):
            content.id
        case let .artistDetail(content, _):
            content.id
        case let .createScene(content):
            content?.id ?? "scene"
        case .alarms:
            "alarms"
        case .addAlarm:
            "addAlarm"
        case let .editAlarm(alarm):
            alarm.id
        }
    }
}
