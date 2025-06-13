import Foundation
import MusicSearchKit
import SonosKit
import SwiftUI
import OrderedCollections

public enum RouterDestination: Hashable, Identifiable {
    case player(groupID: String)
    case groupDestination(content: PlayableContent, position: QueuePosition = .now)
    case manageScenes
    case createScene
    case mediaDetail(content: PlayableContent, group: GroupRoom?)
    case artistDetail(content: PlayableContent, group: GroupRoom?)
    case alarms
    case addAlarm(group: GroupRoom? = nil)
    case editAlarm(alarm: Alarm)
    case speakerSettingsList
    case speakerSettings(room: Room)
    case playableContentList(group: GroupRoom? = nil, contentType: ContentType)
    case playableLibraryList(title: String, items: Binding<OrderedSet<PlayableContent>>, action: ((Int) async -> Void))
    case playableGridScreen(title: String, items: Binding<OrderedSet<PlayableContent>>, action: ((Int) async -> Void))
    case fullPlayHistoryList
    case servicePreferenceScreen
    case houseHold
    case spotifyUserPlaylist
    case genreList
    case playableList(title: String, action: ((Int) async -> [PlayableContent]))
    case connectByIP

    public var id: String {
        switch self {
        case let .player(groupID):
            return groupID
        case let .groupDestination(content, _):
            return content.content.id
        case .manageScenes:
            return "manageScenes"
        case let .mediaDetail(content, _):
            return content.id
        case let .artistDetail(content, _):
            return content.id
        case .createScene:
            return "scene"
        case .alarms:
            return "alarms"
        case .addAlarm:
            return "addAlarm"
        case let .editAlarm(alarm):
            return alarm.id
        case .speakerSettingsList:
            return "speakerSettingsList"
        case .speakerSettings:
            return "speaker.configuration"
        case .playableContentList(_, _):
            return "playableContentList"
        case .fullPlayHistoryList:
            return "fullPlayHistoryList"
        case .playableLibraryList(title: _, items: _, action: _):
            return "playableLibraryList"
        case .playableGridScreen(title: _, items: _, action: _):
            return "playableGridScreen"
        case .houseHold:
            return "houseHold"
        case .servicePreferenceScreen:
            return "servicePreferenceScreen"
        case .spotifyUserPlaylist:
            return "spotifyUserPlaylist"
        case .genreList:
            return "genre"
        case .playableList(let title, _):
            return title
        default:
            return self.id
        }
    }

    public static func ==(lhs: RouterDestination, rhs: RouterDestination) -> Bool {
        switch (lhs, rhs) {
        case let (.player(groupID1), .player(groupID2)):
            return groupID1 == groupID2
        case let (.groupDestination(content1, position1), .groupDestination(content2, position2)):
            return content1 == content2 && position1 == position2
        case (.manageScenes, .manageScenes):
            return true
        case (.createScene, .createScene):
            return true
        case let (.mediaDetail(content1, group1), .mediaDetail(content2, group2)):
            return content1 == content2 && group1 == group2
        case let (.artistDetail(content1, group1), .artistDetail(content2, group2)):
            return content1 == content2 && group1 == group2
        case (.alarms, .alarms):
            return true
        case let (.addAlarm(group1), .addAlarm(group2)):
            return group1 == group2
        case let (.editAlarm(alarm1), .editAlarm(alarm2)):
            return alarm1 == alarm2
        case (.speakerSettingsList, .speakerSettingsList):
            return true
        case let (.speakerSettings(room1), .speakerSettings(room2)):
            return room1 == room2
        case let (.playableContentList(group1, contentType1), .playableContentList(group2, contentType2)):
            return group1 == group2 && contentType1 == contentType2
        case let (.playableLibraryList(_, items1, _), .playableLibraryList(_, items2, _)):
            return items1.wrappedValue == items2.wrappedValue
        case let (.playableList(title, _), .playableList(title2, _)):
            return title == title2
        case let (.playableGridScreen(_, items1, _), .playableGridScreen(_, items2, _)):
            return items1.wrappedValue == items2.wrappedValue
        case (.fullPlayHistoryList, .fullPlayHistoryList):
            return true
        case (.spotifyUserPlaylist, .spotifyUserPlaylist):
            return true
        case (.genreList, .genreList):
            return true
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .player(groupID):
            hasher.combine(groupID)
        case let .groupDestination(content, position):
            hasher.combine(content)
            hasher.combine(position)
        case .manageScenes:
            hasher.combine("manageScenes")
        case let .mediaDetail(content, group):
            hasher.combine(content)
            hasher.combine(group)
        case let .artistDetail(content, group):
            hasher.combine(content)
            hasher.combine(group)
        case .createScene:
            hasher.combine("scene")
        case .alarms:
            hasher.combine("alarms")
        case .addAlarm:
            hasher.combine("addAlarm")
        case let .editAlarm(alarm):
            hasher.combine(alarm)
        case .speakerSettingsList:
            hasher.combine("speakerSettingsList")
        case let .speakerSettings(room):
            hasher.combine(room)
        case let .playableContentList(group, contentType):
            hasher.combine(group)
            hasher.combine(contentType)
        case let .playableLibraryList(_, items, _):
            hasher.combine(items.wrappedValue)
        case let .playableGridScreen(_, items, _):
            hasher.combine(items.wrappedValue)
        case .fullPlayHistoryList:
            hasher.combine("fullPlayHistoryList")
        case .houseHold:
            hasher.combine("houseHolds")
        case .servicePreferenceScreen:
            hasher.combine("servicePreferenceScreen")
        case .spotifyUserPlaylist:
            hasher.combine("spotifyUserPlaylist")
        case .genreList:
            hasher.combine("genreList")
        case .playableList(let title, action: _):
            hasher.combine(title)
        default:
            hasher.combine(self)
        }
    }
}
