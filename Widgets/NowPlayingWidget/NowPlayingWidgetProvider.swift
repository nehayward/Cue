import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct NowPlayingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), configuration: ConfigurationNowPlayingAppIntent(), info: nil)
    }

    func snapshot(for configuration: ConfigurationNowPlayingAppIntent, in context: Context) async -> NowPlayingEntry {
        let sonosService = SonosService()
        await sonosService.load()
        guard let group = sonosService.groups.first(where: \.coordinatorRoom.isPlaying) else {
            return NowPlayingEntry(date: .now, configuration: configuration, info: nil)
        }

        let volume = await sonosService.getVolume(ip: group.coordinatorRoom.ip)
        guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else {
            return NowPlayingEntry(date: Date(), configuration: configuration, info: nil)
        }

        guard let artworkURL = await sonosService.getArtwork(song: track.name, artist: track.artist, album: track.album) else {
            return NowPlayingEntry(date: Date(), configuration: configuration, info: .init(data: nil, room: group.coordinatorRoom.name , track: track.name, artist: track.artist))
        }

        let data = try? await URLSession.shared.data(from: artworkURL)
        let entry = NowPlayingEntry(date: .now, configuration: configuration, info: .init(data: data?.0, room: group.coordinatorRoom.name, track: track.name, artist: track.artist))
        return entry
    }

    func timeline(for configuration: ConfigurationNowPlayingAppIntent, in context: Context) async -> Timeline<NowPlayingEntry> {
        var entries: [NowPlayingEntry] = []
        let sonosService = SonosService()
        await sonosService.load()
        guard let group = sonosService.groups.first(where: \.coordinatorRoom.isPlaying) else {
            let entry = NowPlayingEntry(date: .now, configuration: configuration, info: nil)
            entries.append(entry)
            return Timeline(entries: entries, policy: .atEnd)
        }

//        let volume = await sonosService.getVolume(ip: group.coordinatorRoom.ip)
        guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else {
            let entry = NowPlayingEntry(date: Date(), configuration: configuration, info: nil)
            entries.append(entry)
            return Timeline(entries: entries, policy: .atEnd)
        }

        guard let artworkURL = await sonosService.getArtwork(song: track.name, artist: track.artist, album: track.album) else {
            let entry = NowPlayingEntry(date: Date(), configuration: configuration, info: .init(data: nil, room: group.coordinatorRoom.name , track: track.name, artist: track.artist))
            entries.append(entry)
            return Timeline(entries: entries, policy: .atEnd)
        }

        let data = try? await URLSession.shared.data(from: artworkURL)
        let entry = NowPlayingEntry(date: .now, configuration: configuration, info: .init(data: data?.0, room: group.coordinatorRoom.name, track: track.name, artist: track.artist))

        entries.append(entry)

        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct NowPlayingEntry: TimelineEntry {
    var date: Date
    let configuration: ConfigurationNowPlayingAppIntent
    let info: Info?

    struct Info {
        let data: Data?
        let room: String
        let track: String
        let artist: String
    }
}
