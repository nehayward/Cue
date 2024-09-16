import AppIntents
import WidgetKit
import SonosKit
import SwiftUI


struct SceneWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = SceneEntry
    typealias Configuration = SceneWidgetConfigurationIntent
    
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), configuration: Configuration(), info: nil)
    }

    func snapshot(for configuration: Configuration, in context: Context) async -> Entry {
        let sonosService = SonosService()
        do {
            try await sonosService.load(useCache: true)
        } catch {
            return Entry(date: .now, configuration: configuration, info: nil)
        }


        guard let group = sonosService.groups.first(where: \.coordinatorRoom.isPlaying) else {
            return Entry(date: .now, configuration: configuration, info: nil)
        }

        guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else {
            return Entry(date: Date(), configuration: configuration, info: nil)
        }

        guard let artworkURL = await sonosService.getArtwork(from: track) else {
            let entity = SonosDeviceEntity(id: group.coordinatorID, ip: group.coordinatorRoom.ip, name: group.coordinatorRoom.name)
            let info = Entry.Info(room: entity, data: nil, track: track.name, artist: track.artist)
            return Entry(date: Date(), configuration: configuration, info: nil)
        }

        let data = try? await URLSession.shared.data(from: artworkURL)
        let entity = SonosDeviceEntity(id: group.coordinatorID, ip: group.coordinatorRoom.ip, name: group.coordinatorRoom.name)
        let info = Entry.Info(room: entity, data: data?.0, track: track.name, artist: track.artist)
        let entry = Entry(date: .now, configuration: configuration, info: info)
        return entry
    }

    func timeline(for configuration: Configuration, in context: Context) async -> Timeline<Entry> {
        let sonosService = SonosService()
        // MARK: Needed for Sonos transitioning delay
        try? await Task.sleep(for: .seconds(2))
        do {
            try await sonosService.load(useCache: true)
        } catch {
            print(error)
            let entry = Entry(date: .now, configuration: configuration, info: nil)
            return Timeline(entries: [entry], policy: .atEnd)
        }

        guard let group = sonosService.groups.first(where: \.coordinatorRoom.isPlaying) else {
            let entry = Entry(date: .now, configuration: configuration, info: nil)
            return Timeline(entries: [entry], policy: .atEnd)
        }

        guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else {
            let entry = Entry(date: Date(), configuration: configuration, info: nil)
            return Timeline(entries: [entry], policy: .atEnd)
        }

        guard let artworkURL = await sonosService.getArtwork(from: track) else {
            let entity = SonosDeviceEntity(id: group.coordinatorID, ip: group.coordinatorRoom.ip, name: group.coordinatorRoom.name)
            let info = Entry.Info(room: entity, data: nil, track: track.name, artist: track.artist)
            let entry = Entry(date: .now, configuration: configuration, info: info)
            return Timeline(entries: [entry], policy: .atEnd)
        }

        let data = try? await URLSession.shared.data(from: artworkURL)
        let entity = SonosDeviceEntity(id: group.coordinatorID, ip: group.coordinatorRoom.ip, name: group.coordinatorRoom.name)
        let info = Entry.Info(room: entity, data: data?.0, track: track.name, artist: track.artist)
        let entry = Entry(date: Date(), configuration: configuration, info: info)
        return Timeline(entries: [entry], policy: .atEnd)
    }
}
