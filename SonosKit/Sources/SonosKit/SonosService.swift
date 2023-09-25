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
    public var lastKnownIP: String { sonosSystemDiscoverService.sonosStorageIP.sonosIP }
    public var state: String { sonosSystemDiscoverService.lastKnownState }


    public var monitorTask: Task<Void, Error> = Task { }
    public var sonosPulse: Task<Void, Error> = Task { }
    public var isRunning: Bool { !sonosPulse.isCancelled }

    public init () { 
        sonosPulse.cancel()
    }

    public var sorted: [GroupRoom] {
        get {
            let sorted = groups.sorted { $0.coordinatorRoom.name < $1.coordinatorRoom.name }
            //        guard superMember.isEnabled else {
            //            if let first = sorted.first {
            //                return [first]
            //            }
            //            return []
            //        }
            return sorted
        } set {
            groups = newValue
        }
    }

    public var sortedRooms: [Room] {
        get {
            let sorted = rooms.sorted { $0.name < $1.name }
            //        guard superMember.isEnabled else {
            //            if let first = sorted.first {
            //                return [first]
            //            }
            //            return []
            //        }
            return sorted
        } set {
            rooms = newValue
        }
    }

    @MainActor
    public func monitor(retry: Bool = true, useCache: Bool = true) {
        if isRunning { return }
        print("Monitoring!")

        self.sonosPulse = Task { [weak self] in
            guard let self else { return }
            var useCache = useCache
            var retry = retry
            repeat {
                do {
                    systemNotFound = false
                    permissionsDenied = false
                    try await load(useCache: useCache)
                    // MARK: Update room volumes
                    if selectedGroup != nil {
                        try? await Task.sleep(for: .milliseconds(500))
                    } else {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    useCache = true
                } catch SonosServiceError.permissionDenied {
                    print("Permission")
                    permissionsDenied = true
                    sonosPulse.cancel()
                }
                catch SonosServiceError.sonosSystemNotFound {
                    guard retry else {
                        print("System not found")
                        systemNotFound = true
                        sonosPulse.cancel()
                        return
                    }
                    // MARK: Invalidate Cache
                    useCache = false
                    retry = false
                }
                catch SonosServiceError.cancelled {

                }
                catch {
                    print(error)
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
    public func monitorWatch(retry: Bool = true, duration: Duration = .seconds(2), useCache: Bool) {
        if isRunning { return }
        print("Monitoring!")
        self.sonosPulse = Task { [weak self] in
            guard let self else { return }
            var useCache = useCache

            repeat {
                do {
                    systemNotFound = false
                    permissionsDenied = false
                    try await fetch(useCache: useCache)
                    try? await Task.sleep(for: duration) // exception thrown when cancelled by SwiftUI when this view disappears.
//                    print("Tock", Date.now)
                    useCache = true
                } catch SonosServiceError.permissionDenied {
                    print("Permision")
                    permissionsDenied = true
                    sonosPulse.cancel()
                }
                catch SonosServiceError.sonosSystemNotFound {
                    print("System not found")
                    systemNotFound = true
                    // MARK: Invalidate Cache
                    useCache = false
                }
                catch SonosServiceError.cancelled {
                    print("It's okay")
                }
                catch {
                    print(error)
                    permissionsDenied = true
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
    public func load(useCache: Bool) async throws {
        let newGroup = try await getGroups(useCache: useCache)
        if !newGroup.isEmpty && Set(newGroup) != Set(self.groups) {
            print("Update")
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
        }
        if let selectedGroup {
//            print("Selected Group")

            guard let groupIndex = groups.firstIndex(where: { group in
                group.coordinatorID == selectedGroup.coordinatorID
            }) else {
                print("Group Changed")
                print(selectedGroup.coordinatorRoom.id)
                print(selectedGroup.coordinatorID)
                for group in groups {
                    print(group.coordinatorRoom.id)
                    print(group.coordinatorID)
                    print("")
                }
                self.selectedGroup = nil
                return
            }

            let roomGroup = groups[groupIndex]
            if roomGroup != selectedGroup {
                self.selectedGroup = roomGroup
            }
            async let track = self.getTrack(ip: roomGroup.coordinatorRoom.ip)
            async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
            async let groupVolume = self.getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
            await updateGroupRooms(from: [roomGroup])
            await updateGroupCheckTVMode(from: [roomGroup])

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

            guard let artworkURL = await self.getArtwork(from: track) else {
                if roomGroup.coordinatorRoom.track != track {
                    roomGroup.coordinatorRoom.track = track
                } else {
                    roomGroup.coordinatorRoom.track.playbackPosition = track.playbackPosition
                }

                return
            }

            if roomGroup.coordinatorRoom.track != track {
                roomGroup.coordinatorRoom.track = track
            } else {
                roomGroup.coordinatorRoom.track.playbackPosition = track.playbackPosition
            }

            roomGroup.coordinatorRoom.track.artworkURL = artworkURL
            return
        }

        try await updateGroups(from: groups)
        await updateGroupRooms(from: groups)
        await updateGroupCheckTVMode(from: groups)
        await updateGroupMuteState(for: groups)

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
    public func fetch(useCache: Bool) async throws {
        let newGroup = try await getGroups(useCache: useCache)
        if !newGroup.isEmpty && Set(newGroup) != Set(self.groups) {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
        }
        if let selectedGroup {
//            print("Selected Group")
//            print(selectedGroup.coordinatorRoom.id)

            guard let groupIndex = groups.firstIndex(where: { group in
                group.coordinatorID == selectedGroup.coordinatorID
            }) else {
                print("Group Changed")
                print(selectedGroup.coordinatorRoom.id)
                print(selectedGroup.coordinatorID)
                for group in groups {
                    print(group.coordinatorRoom.id)
                    print(group.coordinatorID)
                    print("")
                }
                self.selectedGroup = nil
                return
            }

            let roomGroup = groups[groupIndex]
//            print(roomGroup == selectedGroup)
            if roomGroup != selectedGroup {
                self.selectedGroup = roomGroup
            }
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
                return
            }
            roomGroup.coordinatorRoom.track = track


            await updateGroupCheckTVMode(from: [groups[groupIndex]])
            await updateGroupRooms(from: [groups[groupIndex]])


//            let previousArtwork = roomGroup.coordinatorRoom.track.artworkURL
//            if previousArtwork != nil {
//                roomGroup.coordinatorRoom.track.artworkURL = previousArtwork
//            }

//            guard let artworkURL = await self.getArtwork(from: track, size: 200) else {
//                roomGroup.coordinatorRoom.track = track
//                return
//            }

//            roomGroup.coordinatorRoom.track.artworkURL = artworkURL
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
        await withDiscardingTaskGroup { group in
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
                    guard let awaitedTrack = await track else {
                        roomGroup.coordinatorRoom.track = .empty
                        return
                    }


                    guard let artworkURL = await self.getArtwork(from: awaitedTrack) else {
                        if roomGroup.coordinatorRoom.track != awaitedTrack {
                            roomGroup.coordinatorRoom.track = awaitedTrack
                        } else {
                            roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                        }
                        return
                    }

                    awaitedTrack.artworkURL = roomGroup.coordinatorRoom.track.artworkURL
                    if artworkURL != awaitedTrack.artworkURL {
                        roomGroup.coordinatorRoom.track.artworkURL = artworkURL
                    }

                    if roomGroup.coordinatorRoom.track != awaitedTrack {
                        roomGroup.coordinatorRoom.track = awaitedTrack
                        roomGroup.coordinatorRoom.track.artworkURL = artworkURL
                    } else {
                        roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                    }

//                    print("Update \(roomGroup.coordinatorRoom.name)")
                }
            }
        }
    }

    @MainActor
    func updateGroupRooms(from roomGroups: [GroupRoom]) async {
        await withDiscardingTaskGroup { group in
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
        let newGroup = try await getGroups(useCache: true)
        if !newGroup.isEmpty && newGroup != groups {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
        }

        await withDiscardingTaskGroup { group in
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
        await withDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                group.addTask {
                    let isTVMode = await self.isTVMode(ip: roomGroup.coordinatorRoom.ip)
                    roomGroup.tvMode = isTVMode
                }
            }
        }
    }

    @MainActor
    public func updateGroupMuteState(for roomGroups: [GroupRoom]) async {
        await withDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                group.addTask {
                    roomGroup.isMuted = await self.isMuted(for: roomGroup)
                }
            }
        }
    }

    @MainActor
    func updateGroupsWatch(from roomGroups: [GroupRoom]) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                group.addTask {
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
                        return
                    }

                    roomGroup.coordinatorRoom.track = track
//                    return (index, roomGroup)
                }
            }
//
//            for try await (index, group) in group {
//                self.groups[index] = group
//            }
        }
    }

    @MainActor
    public func getGroups(useCache: Bool) async throws -> [GroupRoom] {
        let ip = try await sonosSystemDiscoverService.getFirstIP(useCache: useCache)
        let groups = try await sonosAPI.getGroups(ipAddress: ip)
        return groups
    }

    public func getGroups(with ip: String) async throws -> [GroupRoom] {
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

    @MainActor
    public func setGroupMute(group: GroupRoom, mute: Bool) async {
        group.isMuted = mute
        await sonosAPI.setGroupMute(IP: group.coordinatorRoom.ip, mute: mute)
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
            guard let artworkString = await musicSearch.appleLookup(id: track.trackID)?.artworkURL(with: "\(size)") else { return nil }
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
        case .airplay, .unknown:
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

    public func isMuted(for group: GroupRoom) async -> Bool {
        await sonosAPI.getGroupMute(IP: group.coordinatorRoom.ip)
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

    public func getCurrentTransportActions(ip: String) async -> AvailableActions? {
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

    // TODO: Create Scene
    public func createScene(rooms: [Room]) async {
//        let rooms = rooms.filter { room in
//            selections.contains(room.id)
//        }
//        let sceneRooms = rooms.map { SceneRoom(id: $0.id, ip: $0.ip, name: $0.name, volume: $0.volume) }
//        let newScene = SonosScene(name: sceneName, rooms: sceneRooms)
//        scenes.append(newScene)
    }

    public func runScene(_ scene: SonosScene) async {
        let rooms = scene.rooms[1...].map { Room(id: $0.id, ip: $0.ip, name: $0.name)}
        await group(rooms: rooms, to: scene.rooms.first!.id)
        for room in scene.rooms {
            await setDeviceVolume(ip: room.ip, volume: Int(room.volume))
        }
    }

    public func queue(song: String, on ip: String) async {
        await sonosAPI.removeAllTrackFromQueue(IP: ip)
        await sonosAPI.queue(song: song, IP: ip)
    }

    public func seek(trackNumber: Int, on group: GroupRoom) async {
        await sonosAPI.setAVTransport(IP: group.coordinatorRoom.ip, ID: group.coordinatorID)
        await sonosAPI.seek(trackNumber: trackNumber, IP: group.coordinatorRoom.ip)
    }

    public func queueSpotifyPlaylist(id: String, title: String, owner: String, on ip: String, group: GroupRoom) async {
        await sonosAPI.removeAllTrackFromQueue(IP: ip)
        await sonosAPI.queueSpotifyPlaylist(ID: id, title: title, owner: owner, IP: ip)
        await sonosAPI.setAVTransport(IP: ip, ID: group.coordinatorID)
    }

    public func queueSpotifyTrack(id: String, group: GroupRoom) async {
        await sonosAPI.removeAllTrackFromQueue(IP: group.coordinatorRoom.ip)
        await sonosAPI.queueSpotifyTrack(ID: id, IP: group.coordinatorRoom.ip)
        await sonosAPI.setAVTransport(IP: group.coordinatorRoom.ip, ID: group.coordinatorID)
    }

    public func getQueue(ip: String) async -> [Track] {
        await sonosAPI.getQueue(IP: ip)
    }

    public func getGroupCoordinatorWithRoom(roomID: String) async -> Room? {
        do {
            let groups = try await getGroups(useCache: true)
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



