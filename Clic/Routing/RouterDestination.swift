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
    case speakerSettingsList
    case speakerSettings(room: Room)
    case playableContentList(group: GroupRoom? = nil, contentType: ContentType)

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
        case .speakerSettingsList:
            "speakerSettingsList"
        case .speakerSettings:
            "speaker.configuration"
        case .playableContentList(_, _):
            "playableContentList"
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        switch self {
        case let .player(groupID):
            hasher.combine(groupID)
        case let .groupDestination(content, position):
            hasher.combine(content.content.id)
            hasher.combine(position)
        case .manageScenes:
            hasher.combine("manageScenes")
        case let .mediaDetail(content, group):
            hasher.combine(content.id)
            hasher.combine(group?.id)
        case let .artistDetail(content, group):
            hasher.combine(content.id)
            hasher.combine(group?.id)
        case let .createScene(content):
            hasher.combine(content?.id ?? "scene")
        case .alarms:
            hasher.combine("alarms")
        case let .addAlarm(group):
            hasher.combine(group?.id)
        case let .editAlarm(alarm):
            hasher.combine(alarm.id)
        case .speakerSettingsList:
            hasher.combine("speakerSettingsList")
        case let .speakerSettings(room):
            hasher.combine(room.id)
        case let .playableContentList(group, contentType):
            hasher.combine(group?.id)
            hasher.combine(contentType)
        }
    }

    public static func == (lhs: RouterDestination, rhs: RouterDestination) -> Bool {
        lhs.id == rhs.id
    }
}
