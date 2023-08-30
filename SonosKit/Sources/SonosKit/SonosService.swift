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
    public var networkMonitorService = NetworkMonitorService()

    public var systemNotFound: Bool = false
    public var permissionsDenied: Bool = false
    public var pulseIsRunning: Bool = false
    public var isSearching: Bool { sonosSystemDiscoverService.isSearching }

    public var monitorTask: Task<Void, Error> = Task { }
    public var sonosPulse: Task<Void, Error> = Task { }
    public var isRunning: Bool { !sonosPulse.isCancelled }

    public init () { 
        sonosPulse.cancel()
    }

    @MainActor
    public var sorted: [GroupRoom] {
        let sorted = groups.sorted { $0.coordinatorRoom.name < $1.coordinatorRoom.name }
//        guard superMember.isEnabled else {
//            if let first = sorted.first {
//                return [first]
//            }
//            return []
//        }
        return sorted
    }

    @MainActor
    public func monitor() {
        if isRunning { return }
        print("Monitoring!")

        self.sonosPulse = Task { [weak self] in
            guard let self else { return }
            repeat {
                do {
                    systemNotFound = false
                    permissionsDenied = false
                    try await load()
                    // MARK: Update room volumes
                    try? await Task.sleep(for: .seconds(1)) // exception thrown when cancelled by SwiftUI when this view disappears.
                    print("Tock", Date.now)

                } catch SonosServiceError.permissionDenied {
                    permissionsDenied = true
                    sonosSystemDiscoverService.lastKnownIP = ""
                    sonosPulse.cancel()
                }
                catch SonosServiceError.sonosSystemNotFound {
                    systemNotFound = true
                    sonosSystemDiscoverService.lastKnownIP = ""
                    sonosPulse.cancel()
                }
                catch {
                    permissionsDenied = true
                    sonosSystemDiscoverService.lastKnownIP = ""
                    sonosPulse.cancel()
                    print(#function, error)
                }
            } while (!sonosPulse.isCancelled)
        }
    }

//    @MainActor
//    public func monitor() {
//        monitorTask = Task { [weak self] in
//            guard let self else { return }
//            systemNotFound = false
//            permissionsDenied = false
//            do {
//                try await load()
//                try? await Task.sleep(for: .seconds(1), clock: .suspending)
//                print("Tock", Date.now)
//                monitor()
//            } catch SonosServiceError.permissionDenied {
//                permissionsDenied = true
//                pulseIsRunning = false
//                sonosSystemDiscoverService.lastKnownIP = ""
//                //                    monitorTask.cancel()
//            }
//            catch SonosServiceError.sonosSystemNotFound {
//                systemNotFound = true
//                sonosSystemDiscoverService.lastKnownIP = ""
//                //                    monitorTask.cancel()
//            }
//            catch {
//                permissionsDenied = true
//                pulseIsRunning = false
//                sonosSystemDiscoverService.lastKnownIP = ""
//
//                //                    monitorTask.cancel()
//                print(#function, error)
//            }
//        }
//    }


    @MainActor
    public func monitorWatch(duration: Duration = .seconds(1)) {
        if isRunning { return }
        print("Monitoring!")
        self.sonosPulse = Task { [weak self] in
            guard let self else { return }
            repeat {
                do {
                    systemNotFound = false
                    permissionsDenied = false
                    try await fetch()
                    try? await Task.sleep(for: duration) // exception thrown when cancelled by SwiftUI when this view disappears.
                    print("Tock", Date.now)

                } catch SonosServiceError.permissionDenied {
                    permissionsDenied = true
                    sonosSystemDiscoverService.lastKnownIP = ""
                    sonosPulse.cancel()
                }
                catch SonosServiceError.sonosSystemNotFound {
                    systemNotFound = true
                    sonosSystemDiscoverService.lastKnownIP = ""
                    sonosPulse.cancel()
                }
                catch {
                    permissionsDenied = true
                    sonosSystemDiscoverService.lastKnownIP = ""
                    sonosPulse.cancel()
                }
            } while (!sonosPulse.isCancelled)
        }

//        Task {
//            try await Task.sleep(for: .seconds(3))
//            sonosPulse.cancel()
//        }
    }

    @MainActor
    public func load() async throws {
        let newGroup = try await getGroups()
        if !newGroup.isEmpty && newGroup != self.groups {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
        }
        try await updateGroups(from: groups)
        await updateGroupRooms(from: groups)
        await updateGroupCheckTVMode(from: groups)

//        for group in groups.indices {
//            let groupVolume = await getGroupVolume(ip: groups[group].coordinatorRoom.ip)
//            groups[group].groupVolume = groupVolume
//
//            for room in groups[group].rooms.indices {
//                let playbackInfo = await getPlaybackInfo(ip: groups[group].rooms[room].ip)
//
//                switch playbackInfo {
//                case .playing:
//                    groups[group].rooms[room].isPlaying = true
//                case .paused:
//                    groups[group].rooms[room].isPlaying = false
//                default: break
//                }
//            }
//
//            for room in groups[group].rooms.indices {
//                let volume = await getVolume(ip: groups[group].rooms[room].ip)
//                groups[group].rooms[room].volume = volume
//
////                if await isTVMode(ip: groups[group].rooms[room].ip) {
////                    groups[group].tvMode = true
////                    groups[group].coordinatorRoom.track = .init(name: "", artist: "", album: "", artworkURL: nil, musicService: .apple, duration: .zero, playbackPosition: .zero)
////                    continue
////                }
////                groups[group].tvMode = false
//
//                guard let track = await getTrack(ip: groups[group].rooms[room].ip) else {
//                    groups[group].rooms[room].track = .init(name: "", artist: "", album: "", artworkURL: nil, musicService: .apple, duration: .zero, playbackPosition: .zero)
//                    continue
//                }
//
//                let previousArtwork = groups[group].rooms[room].track.artworkURL
//
//                groups[group].rooms[room].track = track
//
//                if previousArtwork != nil {
//                    groups[group].rooms[room].track.artworkURL = previousArtwork
//                }
//
//                guard let artworkURL = await getArtwork(from: track) else {
//                    continue
//                }
//
//                if artworkURL != previousArtwork {
//                    groups[group].rooms[room].track.artworkURL = artworkURL
//                }
//            }
//        }
//        return
    }

    @MainActor
    public func fetch() async throws {
        let newGroup = try await getGroups()
        if !newGroup.isEmpty && newGroup != groups {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
        }
        if let selectedGroup {
            print("Selected Group")

            guard let groupIndex = groups.firstIndex(of: selectedGroup) else {
                self.selectedGroup = nil
                return
            }
            let roomGroup = groups[groupIndex]
            async let track = self.getTrack(ip: roomGroup.coordinatorRoom.ip)
            async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
            async let groupVolume = self.getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
            async let _ = updateGroupRooms(from: [groups[groupIndex]])

            switch await playbackInfo {
            case .playing:
                roomGroup.coordinatorRoom.isPlaying = true
            case .paused:
                roomGroup.coordinatorRoom.isPlaying = false
            default:
                break
            }

            roomGroup.groupVolume = await groupVolume
            guard let track = await track else {
                return
            }

            let previousArtwork = roomGroup.coordinatorRoom.track.artworkURL
            if previousArtwork != nil {
                roomGroup.coordinatorRoom.track.artworkURL = previousArtwork
            }

            guard let artworkURL = await self.getArtwork(from: track, size: 100) else {
                roomGroup.coordinatorRoom.track = track
                return
            }

            roomGroup.coordinatorRoom.track = track
            roomGroup.coordinatorRoom.track.artworkURL = artworkURL
            return
        }

        try await updateGroupsWatch(from: groups)
        await updateGroupRooms(from: groups)
        await updateGroupCheckTVMode(from: groups)

//        for groupIndex in groups.indices {
//            async let track = getTrack(ip: groups[groupIndex].coordinatorRoom.ip)
//            async let playbackInfo = getPlaybackInfo(ip: groups[groupIndex].coordinatorRoom.ip)
//            async let groupVolume = getGroupVolume(ip: groups[groupIndex].coordinatorRoom.ip)
//
//            switch await playbackInfo {
//            case .playing:
//                groups[groupIndex].coordinatorRoom.isPlaying = true
//            case .paused:
//                groups[groupIndex].coordinatorRoom.isPlaying = false
//            default:
//                break
//            }
//
//            if let track = await track {
//                groups[groupIndex].coordinatorRoom.track = track
//            }
//
//            groups[groupIndex].groupVolume = await groupVolume
//
//            for roomIndex in groups[groupIndex].rooms.indices {
//                let volume = await getVolume(ip: groups[groupIndex].rooms[roomIndex].ip)
//                groups[groupIndex].rooms[roomIndex].volume = volume
//            }
//        }

        return
    }


    @MainActor
    func updateGroups(from groups: [GroupRoom]) async throws {
        await withTaskGroup(of: (Void).self) { group in
            for roomGroup in groups {
                group.addTask{
                    async let track = self.getTrack(ip: roomGroup.coordinatorRoom.ip)
                    async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
                    async let groupVolume = self.getGroupVolume(ip: roomGroup.coordinatorRoom.ip)

                    switch await playbackInfo {
                    case .playing:
                        roomGroup.coordinatorRoom.isPlaying = true
                    case .paused:
                        roomGroup.coordinatorRoom.isPlaying = false
                    default:
                        break
                    }

                    roomGroup.groupVolume = await groupVolume
                    guard let track = await track else {
                        roomGroup.coordinatorRoom.track = Track(trackID: "", name: "", artist: "", album: "", musicService: .apple, duration: 0, playbackPosition: 0)
                        return
                    }

                    let previousArtwork = roomGroup.coordinatorRoom.track.artworkURL
                    if previousArtwork != nil {
                        roomGroup.coordinatorRoom.track.artworkURL = previousArtwork
                    }

                    guard let artworkURL = await self.getArtwork(from: track) else {
                        roomGroup.coordinatorRoom.track = track
                        return
                    }

                    roomGroup.coordinatorRoom.track = track
                    roomGroup.coordinatorRoom.track.artworkURL = artworkURL
                }
            }
        }
    }

    @MainActor
    func updateGroupRooms(from roomGroups: [GroupRoom]) async {
        await withTaskGroup(of: (Void).self) { group in
            for roomGroup in roomGroups {
                for room in roomGroup.rooms {
                    group.addTask {
                        let volume = await self.getVolume(ip: room.ip)
                        room.volume = volume
                    }
                }
            }
        }
    }

    @MainActor
    public func updateGroupsCheckPlayback() async throws {
        let newGroup = try await getGroups()
        if !newGroup.isEmpty && newGroup != groups {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
        }

        await withThrowingTaskGroup(of: (Void).self) { group in
            for (_, roomGroup) in groups.enumerated() {
                group.addTask{
                    async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
                    switch await playbackInfo {
                    case .playing:
                        roomGroup.coordinatorRoom.isPlaying = true
                    case .paused:
                        roomGroup.coordinatorRoom.isPlaying = false
                    default:
                        break
                    }
                }
            }
        }
    }

    @MainActor
    func updateGroupCheckTVMode(from roomGroups: [GroupRoom]) async {
        await withTaskGroup(of: (Void).self) { group in
            for roomGroup in roomGroups {
                group.addTask {
                    let isTVMode = await self.isTVMode(ip: roomGroup.coordinatorRoom.ip)
                    roomGroup.tvMode = isTVMode
                }
            }
        }
    }

    @MainActor
    func updateGroupsWatch(from groups: [GroupRoom]) async throws {
        try await withThrowingTaskGroup(of: (Int, GroupRoom).self) { group in
            for (index, roomGroup) in groups.enumerated() {
                group.addTask{
                    async let track = self.getTrack(ip: roomGroup.coordinatorRoom.ip)
                    async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
                    async let groupVolume = self.getGroupVolume(ip: roomGroup.coordinatorRoom.ip)

                    switch await playbackInfo {
                    case .playing:
                        roomGroup.coordinatorRoom.isPlaying = true
                    case .paused:
                        roomGroup.coordinatorRoom.isPlaying = false
                    default:
                        break
                    }

                    roomGroup.groupVolume = await groupVolume

                    guard let track = await track else {
                        return (index, roomGroup)
                    }

                    roomGroup.coordinatorRoom.track = track
                    return (index, roomGroup)
                }
            }

            for try await (index, group) in group {
                self.groups[index] = group
            }
        }
    }

    @MainActor
    public func getGroups() async throws -> [GroupRoom] {
        let ip = try await sonosSystemDiscoverService.getFirstIP()
        let groups = try await sonosAPI.getGroups(ipAddress: ip)
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
            case let .insert(_, element, _):
                print(element)
                await sonosAPI.group(IP: element.ip, to: group.coordinatorID)
            case let .remove(_, element, _):
                print(element)
                await sonosAPI.ungroup(IP: element.ip)
            }
        }
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

    public func getArtwork(from track: Track, size: Int = 500) async -> URL? {
        switch track.musicService  {
        case .apple:
            guard let artworkString = await musicSearch.appleLookup(id: track.trackID)?.artworkURL else { return nil }
            guard let url = URL(string: artworkString) else { return nil }
            return url
        case .spotify:
            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return nil }
            if size == 100, let image = spotifyTrack.album.images.sorted(by: { $0.height ?? 0 < $1.height ?? 0 } ).first {
                guard let url = URL(string: image.url) else { return nil }
                return url
            }

            guard let artworkString = spotifyTrack.album.images.first?.url, let url = URL(string: artworkString) else { return nil }
            return url
        case .airplay:
            let searchResults = await musicSearch.search(song: track.name, artist: track.artist)
            let found = searchResults.first { result in
                result.artistName == track.artist &&
                (result.trackName == track.name || result.trackCensoredName == track.name)
            }
            guard let artworkString = found?.artworkURL(with: "\(size)"), let url = URL(string: artworkString) else { return nil }
            return url
        }
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

    public func getPlaybackInfo(ip: String) async -> PlaybackStatus {
        await sonosAPI.isPlaying(ipAddress: ip)
    }

    public func getCurrentTransportActions(ip: String) async -> AvailableActions {
        await sonosAPI.getCurrentTransportActions(IP: ip)
    }

    public func isTVMode(ip: String) async -> Bool {
        await sonosAPI.mediaInfo(ipAddress: ip)
    }

    public func playPauseDevice(ip: String) async {
        let playback =  await sonosAPI.isPlaying(ipAddress: ip)
        switch playback {
        case .playing:
            await sonosAPI.pause(ipAddress: ip)
        case .paused, .transitioning:
            await sonosAPI.play(ipAddress: ip)
        }
    }

    public func createScene(rooms: [Room]) async {
//        group(rooms: rooms, to: rooms.first.id)
        print(rooms)
    }

    public func runScene(rooms: [Room]) async {
//        group(rooms: rooms, to: rooms.first.id)
        print(rooms)
    }

    public func queue(song: String, on ip: String) async {
        await sonosAPI.removeAllTrackFromQueue(IP: ip)
        await sonosAPI.queue(song: song, IP: ip)
    }

    public func queueSpotifyPlaylist(id: String, title: String, owner: String, on ip: String, group: GroupRoom) async {
        await sonosAPI.removeAllTrackFromQueue(IP: ip)
        await sonosAPI.queueSpotifyPlaylist(ID: id, title: title, owner: owner, IP: ip)
        await sonosAPI.setAVTransport(IP: ip, ID: group.coordinatorID)
    }

    public func getQueue(ip: String) async -> [Track] {
        await sonosAPI.getQueue(IP: ip)
    }

    public func getGroupCoordinatorWithRoom(roomID: String) async -> Room? {
        do {
            let groups = try await getGroups()
            let group = groups.first { group in
                group.rooms.contains { room in
                    room.id == roomID
                }
            }
            return group?.coordinatorRoom
        } catch {
            print(error)
            return nil
        }
    }

    public func pulse() async {
        do {
            print("Pulse")
            try await sonosAPI.pulse()
            print("Good IP Still")
            permissionsDenied = false
            pulseIsRunning = true
        } catch is URLError {
            permissionsDenied = true
            pulseIsRunning = false
        } catch {

        }
    }
}



