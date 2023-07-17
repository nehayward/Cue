import Foundation
import Combine
import MusicSearchKit
import Observation
import SwiftUI

@Observable
public final class SonosService {
    public var groups: [GroupRoom] = []
    public var rooms: [Room] = []
    public var selectedGroup: GroupRoom? = nil

    private var sonosSystemDiscoverService = SonosSystemDiscoverService()
    private var sonosAPI = SonosAPI()
    private var musicSearch = MusicSearchService()

    public init () {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            monitor()
        }
    }

    public func monitor() {
        Task {
            repeat {
                // code you want to repeat
                await load()
                try? await Task.sleep(for: .seconds(1)) // exception thrown when cancelled by SwiftUI when this view disappears.
            } while (!Task.isCancelled)
        }
    }


    public func monitorWatch(frequency: TimeInterval = 1) {
        Task {
            repeat {
                // code you want to repeat
                await fetch()
                try? await Task.sleep(for: .seconds(frequency)) // exception thrown when cancelled by SwiftUI when this view disappears.
            } while (!Task.isCancelled)
        }
    }

    @MainActor
    public func load() async {
        let groups = await getGroups()
        for group in groups.indices {
            let groupVolume = await getGroupVolume(ip: groups[group].coordinatorRoom.ip)
            groups[group].groupVolume = groupVolume

            for room in groups[group].rooms.indices {
                let volume = await getVolume(ip: groups[group].rooms[room].ip)
                groups[group].rooms[room].volume = volume

                let playbackInfo = await getPlaybackInfo(ip: groups[group].rooms[room].ip)
                groups[group].rooms[room].isPlaying = playbackInfo == "PLAYING"

//                if playbackInfo != "PLAYING", !groups[group].rooms[room].track.name.isEmpty {
//                    continue
//                }

                guard let track = await getTrack(ip: groups[group].rooms[room].ip) else { continue }
                groups[group].rooms[room].track = track

                guard let artworkURL = await getArtwork(song: track.name, artist: track.artist, album: track.album) else {
                    continue
                }
                if artworkURL != track.artworkURL {
                    track.artworkURL = artworkURL
                }
            }
        }

        self.groups = groups
        self.rooms = groups.flatMap(\.rooms)
        return
    }

    @MainActor
    public func fetch() async {
        let groups = await getGroups()
        if self.groups.isEmpty || groups.count != self.groups.count {
            self.groups = groups
        }

        if let selectedGroup {
            guard let index = groups.firstIndex(of: selectedGroup) else {
                self.selectedGroup = nil
                return
            }

            let groupVolume = await getGroupVolume(ip: groups[index].coordinatorRoom.ip)
            groups[index].groupVolume = groupVolume
            
            for room in groups[index].rooms.indices {
                let volume = await getVolume(ip: groups[index].rooms[room].ip)
                groups[index].rooms[room].volume = volume
                
                let playbackInfo = await getPlaybackInfo(ip: groups[index].rooms[room].ip)
                groups[index].rooms[room].isPlaying = playbackInfo == "PLAYING"

//                if playbackInfo != "PLAYING" {
//                    continue
//                }

                guard let track = await getTrack(ip: groups[index].rooms[room].ip) else { continue }
                groups[index].rooms[room].track = track
                
                guard let artworkURL = await getArtwork(song: track.name, artist: track.artist, album: track.album) else {
                    continue
                }
                if artworkURL != track.artworkURL {
                    track.artworkURL = artworkURL
                }
            }
            
            return
        }

        for group in groups.indices {
            for room in groups[group].rooms.indices {
                let volume = await getVolume(ip: groups[group].rooms[room].ip)
                groups[group].rooms[room].volume = volume

                let playbackInfo = await getPlaybackInfo(ip: groups[group].rooms[room].ip)
                groups[group].rooms[room].isPlaying = playbackInfo == "PLAYING"

//                if playbackInfo != "PLAYING" {
//                    continue
//                }

                guard let track = await getTrack(ip: groups[group].rooms[room].ip) else { continue }
                groups[group].rooms[room].track = track

                guard let artworkURL = await getArtwork(song: track.name, artist: track.artist, album: track.album) else {
                    continue
                }
                if artworkURL != track.artworkURL {
                    track.artworkURL = artworkURL
                }
            }
        }

        self.groups = groups
        self.rooms = groups.flatMap(\.rooms)
        return
    }

    public func getGroups() async -> [GroupRoom] {
        guard let ip = try? await sonosSystemDiscoverService.getFirstIP() else { return [] }
        let groups = await sonosAPI.getGroups(ipAddress: ip)
        return groups
    }

    public func group(rooms: [Room], to coordinatorID: String) async {
        // MARK: Only group new rooms
        let nonCoordinatorRooms = rooms.filter{ $0.id != coordinatorID } 
        for room in nonCoordinatorRooms {
            await sonosAPI.group(IP: room.ip, to: coordinatorID)
        }
    }

    public func smartGroup(rooms: [Room], to group: GroupRoom) async {
        // MARK: Only group new rooms
        let nonCoordinatorRooms = group.rooms.filter{ $0.id != group.coordinatorID }
        let changes = rooms.difference(from: nonCoordinatorRooms)


        for change in changes {
            switch change {
            case let .insert(offset, element, associatedWith):
                print(element)
                await sonosAPI.group(IP: element.ip, to: group.coordinatorID)
            case let .remove(offset, element, associatedWith):
                print(element)
                await sonosAPI.ungroup(IP: element.ip)
            }
        }
        selectedGroup = nil
    }


    public func setDeviceVolume(ip: String, volume: Int) async {
        await sonosAPI.setVolume(ipAddress: ip, volume: volume)
    }


    public func setGroupVolume(ip: String, volume: Int) async {
        await sonosAPI.setVolume(ipAddress: ip, volume: volume)
    }

    public func setRelativeVolume(ip: String, volume: Int) async {
        await sonosAPI.setRelativeVolume(ipAddress: ip, volume: volume)
    }
    
    public func getTrack(ip: String) async -> Track? {
        await sonosAPI.getCurrentTrack(ipAddress: ip)
    }

    public func getArtwork(song: String, artist: String, album: String) async -> URL? {
        let searchResults = await musicSearch.search(song: song, artist: artist)
        print(searchResults.first)
        let found = searchResults.first { result in
            result.artistName == artist &&
            (result.trackName == song || result.trackCensoredName == song) &&
            result.album == album
        }
        guard let artworkString = found?.artworkURL, let url = URL(string: artworkString) else { return nil }
        return url
    }


    public func pause(ip: String) async {
        await sonosAPI.pause(ipAddress: ip)
    }

    public func play(ip: String) async {
        await sonosAPI.play(ipAddress: ip)
    }

    public func next(ip: String) async {
        await sonosAPI.next(ipAddress: ip)
    }

    public func getVolume(ip: String) async -> Double {
        await sonosAPI.getVolume(ipAddress: ip)
    }

    public func getGroupVolume(ip: String) async -> Double {
        await sonosAPI.getGroupVolume(ipAddress: ip)
    }

    public func getPlaybackInfo(ip: String) async -> String {
        await sonosAPI.playbackInfo(ipAddress: ip)
    }

    public func playDevice(ip: String) async {
        let playback =  await sonosAPI.playbackInfo(ipAddress: ip)
        if playback == "PLAYING" {
            await sonosAPI.pause(ipAddress: ip)
        } else {
            await sonosAPI.play(ipAddress: ip)
        }
    }

    public func queue(song: String, on ip: String) async {
        await sonosAPI.removeAllTrackFromQueue(IP: ip)
        await sonosAPI.queue(song: song, IP: ip)
    }

//    /// This will listen and update the Sonos volume
//    public func monitorVolume(sonos: SonosDevice) async {
//        let SID = await sonosAPI.monitorRenderingControl(ip: sonos.ipAddress)
//        print(SID)
//    }
//
//    /// This will listen and update the Sonos volume
//    public func monitorAVTransport(sonos: SonosDevice) async {
//        let SID = await sonosAPI.monitorAVTransport(ip: sonos.ipAddress)
//        print(SID)
//    }

    public func monitorZones(ip: String) async {
        let SID = await sonosAPI.monitorZones(ip: ip)
        print(SID)
    }
}



