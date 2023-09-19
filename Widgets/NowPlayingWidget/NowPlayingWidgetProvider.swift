import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct NowPlayingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), configuration: NowPlayingWidgetConfigurationIntent(), info: nil)
    }

    func snapshot(for configuration: NowPlayingWidgetConfigurationIntent, in context: Context) async -> NowPlayingEntry {
        let sonosService = SonosService()
        do {
            try await sonosService.load(useCache: true)
        } catch {
            print(error)
            return NowPlayingEntry(date: .now, configuration: configuration, info: nil)
        }


        guard let group = sonosService.groups.first(where: \.coordinatorRoom.isPlaying) else {
            return NowPlayingEntry(date: .now, configuration: configuration, info: nil)
        }

        guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else {
            return NowPlayingEntry(date: Date(), configuration: configuration, info: nil)
        }

        guard let artworkURL = await sonosService.getArtwork(from: track) else {
            let entity = SonosDeviceEntity(id: group.coordinatorID, name: group.coordinatorRoom.name, ip: group.coordinatorRoom.ip, volume: group.groupVolume)
            let info = NowPlayingEntry.Info(room: entity, data: nil, track: track.name, artist: track.artist)
            return NowPlayingEntry(date: Date(), configuration: configuration, info: info)
        }

        let data = try? await URLSession.shared.data(from: artworkURL)
        let entity = SonosDeviceEntity(id: group.coordinatorID, name: group.coordinatorRoom.name, ip: group.coordinatorRoom.ip, volume: group.groupVolume)
        let info = NowPlayingEntry.Info(room: entity, data: data?.0, track: track.name, artist: track.artist)
        let entry = NowPlayingEntry(date: .now, configuration: configuration, info: info)
        return entry
    }

    func timeline(for configuration: NowPlayingWidgetConfigurationIntent, in context: Context) async -> Timeline<NowPlayingEntry> {
        let sonosService = SonosService()
        // MARK: Needed for Sonos transitioning delay
        try? await Task.sleep(for: .seconds(2))
        do {
            try await sonosService.load(useCache: true)
        } catch {
            print(error)
            let entry = NowPlayingEntry(date: .now, configuration: configuration, info: nil)
            return Timeline(entries: [entry], policy: .atEnd)
        }

        guard let group = sonosService.groups.first(where: \.coordinatorRoom.isPlaying) else {
            let entry = NowPlayingEntry(date: .now, configuration: configuration, info: nil)
            return Timeline(entries: [entry], policy: .atEnd)
        }

        guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else {
            let entry = NowPlayingEntry(date: Date(), configuration: configuration, info: nil)
            return Timeline(entries: [entry], policy: .atEnd)
        }

        guard let artworkURL = await sonosService.getArtwork(from: track) else {
            let entity = SonosDeviceEntity(id: group.coordinatorID, name: group.coordinatorRoom.name, ip: group.coordinatorRoom.ip, volume: group.groupVolume)
            let info = NowPlayingEntry.Info(room: entity, data: nil, track: track.name, artist: track.artist)
            let entry = NowPlayingEntry(date: .now, configuration: configuration, info: info)
            return Timeline(entries: [entry], policy: .atEnd)
        }

        let data = try? await URLSession.shared.data(from: artworkURL)
        let entity = SonosDeviceEntity(id: group.coordinatorID, name: group.coordinatorRoom.name, ip: group.coordinatorRoom.ip, volume: group.groupVolume)
        let info = NowPlayingEntry.Info(room: entity, data: data?.0, track: track.name, artist: track.artist)
        let entry = NowPlayingEntry(date: Date(), configuration: configuration, info: info)
        return Timeline(entries: [entry], policy: .atEnd)
    }
}

struct NowPlayingEntry: TimelineEntry {
    var date: Date
    let configuration: NowPlayingWidgetConfigurationIntent
    let info: Info?

    struct Info {
        let room: SonosDeviceEntity
        let data: Data?
        let track: String
        let artist: String
    }
}
