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
        let newGroup = await getGroups()
        if !newGroup.isEmpty && newGroup.count != self.groups.count {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
        }

        for group in groups.indices {
            let groupVolume = await getGroupVolume(ip: groups[group].coordinatorRoom.ip)
            groups[group].groupVolume = groupVolume

            for room in groups[group].rooms.indices {
                let playbackInfo = await getPlaybackInfo(ip: groups[group].rooms[room].ip)
                if playbackInfo == "PLAYING" {
                    groups[group].rooms[room].isPlaying = true
                } else if playbackInfo == "PAUSED_PLAYBACK" || playbackInfo == "STOPPED" {
                    groups[group].rooms[room].isPlaying = false
                }
            }

            for room in groups[group].rooms.indices {
                let volume = await getVolume(ip: groups[group].rooms[room].ip)
                groups[group].rooms[room].volume = volume

                guard let track = await getTrack(ip: groups[group].rooms[room].ip) else { continue }

                let previousArtwork = track.artworkURL

                guard let artworkURL = await getArtwork(song: track.name, artist: track.artist, album: track.album) else {
                    continue
                }
                if artworkURL != previousArtwork {
                    groups[group].rooms[room].track = track
                    groups[group].rooms[room].track.artworkURL = artworkURL
                }
                groups[group].rooms[room].track = track
            }
        }
        return
    }

    @MainActor
    public func fetch() async {
        let newGroup = await getGroups()
        if !newGroup.isEmpty && newGroup.count != self.groups.count {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
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
                if playbackInfo == "PLAYING" {
                    groups[index].rooms[room].isPlaying = true
                } else if playbackInfo == "PAUSED_PLAYBACK" || playbackInfo == "STOPPED" {
                    groups[index].rooms[room].isPlaying = false
                }

                guard let track = await getTrack(ip: groups[index].rooms[room].ip) else { continue }

                let previousArtwork = track.artworkURL

                guard let artworkURL = await getArtwork(song: track.name, artist: track.artist, album: track.album, size: 100) else {
                    continue
                }
                if artworkURL != previousArtwork {
                    groups[index].rooms[room].track = track
                    groups[index].rooms[room].track.artworkURL = artworkURL
                }
                groups[index].rooms[room].track = track
            }
            
            return
        }

        for group in groups.indices {
            for room in groups[group].rooms.indices {
                let playbackInfo = await getPlaybackInfo(ip: groups[group].rooms[room].ip)
                if playbackInfo == "PLAYING" {
                    groups[group].rooms[room].isPlaying = true
                } else if playbackInfo == "PAUSED_PLAYBACK" || playbackInfo == "STOPPED" {
                    groups[group].rooms[room].isPlaying = false
                }
            }

            let groupVolume = await getGroupVolume(ip: groups[group].coordinatorRoom.ip)
            groups[group].groupVolume = groupVolume

            for room in groups[group].rooms.indices {
                let volume = await getVolume(ip: groups[group].rooms[room].ip)
                groups[group].rooms[room].volume = volume

                guard let track = await getTrack(ip: groups[group].rooms[room].ip) else { continue }
                groups[group].rooms[room].track = track
            }
        }

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

    public func setRelativeVolume(ip: String, volume: Int) async {
        await sonosAPI.setRelativeVolume(ipAddress: ip, volume: volume)
    }


    public func setGroupVolume(ip: String, volume: Int) async {
        await sonosAPI.setGroupVolume(ipAddress: ip, volume: volume)
    }

    public func setRelativeGroupVolume(ip: String, volume: Int) async {
        await sonosAPI.setRelativeGroupVolume(ipAddress: ip, volume: volume)
    }

    public func snapShotGroup(ip: String) async {
        await sonosAPI.snapshotGroupVolume(ipAddress: ip)
    }

    public func getTrack(ip: String) async -> Track? {
        await sonosAPI.getCurrentTrack(ipAddress: ip)
    }

    public func getArtwork(song: String, artist: String, album: String, size: Int = 500) async -> URL? {
        let searchResults = await musicSearch.search(song: song, artist: artist)
        let found = searchResults.first { result in
            result.artistName == artist &&
            (result.trackName == song || result.trackCensoredName == song) &&
            result.album == album
        }
        guard let artworkString = found?.artworkURL(with: "\(size)"), let url = URL(string: artworkString) else { return nil }
        return url
    }

    public func pause(ip: String) async {
        let groupIndex = groups.firstIndex { room in
            room.coordinatorRoom.ip == ip
        }

        if let groupIndex {
            for (index, _) in groups[groupIndex].rooms.enumerated() {
                groups[groupIndex].rooms[index].isPlaying = false
            }
        }

        await sonosAPI.pause(ipAddress: ip)
    }

    public func play(ip: String) async {
        let groupIndex = groups.firstIndex { room in
            room.coordinatorRoom.ip == ip
        }

        if let groupIndex {
            for (index, _) in groups[groupIndex].rooms.enumerated() {
                groups[groupIndex].rooms[index].isPlaying = true
            }
        }
        await sonosAPI.play(ipAddress: ip)
    }

    public func next(ip: String) async {
        await sonosAPI.next(ipAddress: ip)
    }

    public func previous(ip: String) async {
        await sonosAPI.previous(ipAddress: ip)
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

    public func playPauseDevice(ip: String) async {
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

    public func getGroupCoordinatorWithRoom(roomID: String) async -> Room? {
        let groups = await getGroups()
        let group = groups.first { group in
            group.rooms.contains { room in
                room.id == roomID
            }
        }
        return group?.coordinatorRoom
    }
}



