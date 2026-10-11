import Foundation
import MusicSearchKit
import SonosKit
import SwiftUI
import OrderedCollections

public enum RouterDestination: Hashable, Identifiable {
    case player(groupID: String)
    case groupDestination(content: PlayableContent, position: QueuePosition = .now)
    case manageScenes
    case createScene(content: PlayableContent?)
    /// `zoomSource` names the tile the push came from, when it came from
    /// one: the screen then zooms out of it instead of sliding in.
    case mediaDetail(content: PlayableContent, group: GroupRoom?, zoomSource: ZoomTransitionSource? = nil)
    case artistDetail(content: PlayableContent, group: GroupRoom?)
    case alarms
    case addAlarm(group: GroupRoom? = nil)
    case editAlarm(alarm: Alarm)
    case speakerSettingsList
    case speakerSettings(room: Room)
    case playableContentList(group: GroupRoom? = nil, contentType: ContentType)
    case playableLibraryList(title: String, items: Binding<OrderedSet<PlayableContent>>, action: ((Int) async -> Void))
    case playableGridScreen(title: String, items: Binding<OrderedSet<PlayableContent>>, sort: PlayableGridSort? = nil, action: ((Int) async -> Void))
    case fullPlayHistoryList
    case servicePreferenceScreen
    /// The download manager: what's coming down, what's here, and the
    /// iCloud Drive side of the Files folder.
    case downloads
    /// What's on this device from one provider — or every provider for
    /// nil — as a small library: Artists, Albums and Songs. A provider's
    /// Downloaded row opens its own.
    case downloaded(service: MusicService?)
    /// One grouped page of the on-device library: what's here by album or
    /// by artist, from one provider or — for Offline Mode — all of them.
    case onDeviceCollection(OnDeviceCollection, service: MusicService? = nil)
    case houseHold
    case spotifyUserPlaylist
    case genreList
    case playableList(title: String, playAllItem: PlayableContent? = nil, showSectionIndex: Bool = true, allowsGrid: Bool = false, sortOptions: [PlayableListSort] = [], sortKey: String? = nil, refreshAction: (() async -> Void)? = nil, searchAction: ((String, Int) async -> [PlayableContent])? = nil, loadingStatus: (() -> String?)? = nil, changeToken: (() -> Int)? = nil, action: ((Int) async -> [PlayableContent])? = nil)
    case folderBrowse(item: PlayableContent, title: String)
    /// A page of TuneIn's directory — a genre, a region, a curated list —
    /// reached from the Radio tab's links. Pages link on to more pages, so
    /// this pushes itself.
    case tuneInBrowse(title: String, url: URL)
    case connectByIP

    public var id: String {
        switch self {
        case let .player(groupID):
            return groupID
        case let .groupDestination(content, _):
            return content.content.id
        case .manageScenes:
            return "manageScenes"
        case let .mediaDetail(content, _, _):
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
        case .playableGridScreen(title: _, items: _, sort: _, action: _):
            return "playableGridScreen"
        case .houseHold:
            return "houseHold"
        case .servicePreferenceScreen:
            return "servicePreferenceScreen"
        case .downloads:
            return "downloads"
        case let .downloaded(service):
            return "downloaded.\(service?.sonosRawValue ?? "all")"
        case let .onDeviceCollection(collection, service):
            return "onDevice.\(collection.title.lowercased()).\(service?.sonosRawValue ?? "all")"
        case .spotifyUserPlaylist:
            return "spotifyUserPlaylist"
        case .genreList:
            return "genre"
        case .playableList(let title, _, _, _, _, _, _, _, _, _, _):
            return title
        case .folderBrowse(let item, _):
            return item.id
        case let .tuneInBrowse(_, url):
            return "tuneInBrowse:\(url.absoluteString)"
        case .connectByIP:
            return "connectByIP"
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
        case let (.mediaDetail(content1, group1, _), .mediaDetail(content2, group2, _)):
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
        case let (.playableList(title, _, _, _, _, _, _, _, _, _, _), .playableList(title2, _, _, _, _, _, _, _, _, _, _)):
            return title == title2
        case let (.folderBrowse(folderID1, title1), .folderBrowse(folderID2, title2)):
            return folderID1 == folderID2 && title1 == title2
        case let (.tuneInBrowse(_, url1), .tuneInBrowse(_, url2)):
            return url1 == url2
        case let (.playableGridScreen(_, items1, _, _), .playableGridScreen(_, items2, _, _)):
            return items1.wrappedValue == items2.wrappedValue
        case (.fullPlayHistoryList, .fullPlayHistoryList):
            return true
        case (.downloads, .downloads):
            return true
        case let (.downloaded(service1), .downloaded(service2)):
            return service1 == service2
        case let (.onDeviceCollection(collection1, service1), .onDeviceCollection(collection2, service2)):
            return collection1 == collection2 && service1 == service2
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
        case let .mediaDetail(content, group, _):
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
        case let .playableGridScreen(_, items, _, _):
            hasher.combine(items.wrappedValue)
        case .fullPlayHistoryList:
            hasher.combine("fullPlayHistoryList")
        case .houseHold:
            hasher.combine("houseHolds")
        case .servicePreferenceScreen:
            hasher.combine("servicePreferenceScreen")
        case .downloads:
            hasher.combine("downloads")
        case let .downloaded(service):
            hasher.combine("downloaded")
            hasher.combine(service)
        case let .onDeviceCollection(collection, service):
            hasher.combine("onDeviceCollection")
            hasher.combine(collection)
            hasher.combine(service)
        case .spotifyUserPlaylist:
            hasher.combine("spotifyUserPlaylist")
        case .genreList:
            hasher.combine("genreList")
        case .playableList(let title, playAllItem: _, showSectionIndex: _, allowsGrid: _, sortOptions: _, sortKey: _, refreshAction: _, searchAction: _, loadingStatus: _, changeToken: _, action: _):
            hasher.combine(title)
        case .folderBrowse(let folderID, let title):
            hasher.combine(folderID)
            hasher.combine(title)
        case let .tuneInBrowse(_, url):
            hasher.combine(url)
        case .connectByIP:
            hasher.combine("connectByIP")
        }
    }
}
