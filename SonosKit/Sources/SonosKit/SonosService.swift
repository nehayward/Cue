import Foundation
import Combine
import OrderedCollections
import MusicSearchKit
import Observation
import SwiftUI

@Observable
public final class SonosService {
    public static var shared = SonosService()

    public var ID: String? = nil
    public var groups: [GroupRoom] = []
    public var zones: OrderedDictionary<String, GroupRoom> = [:]

    public var rooms: [Room] = []
    public var selectedGroup: GroupRoom? = nil
    @ObservationIgnored public var networkMonitorService = NetworkMonitorService()

    @ObservationIgnored private var sonosSystemDiscoverService = SonosSystemDiscoverService()
    @ObservationIgnored private var api = SonosAPI()
    @ObservationIgnored private var musicSearch = MusicSearchService()

    public var systemNotFound: Bool = false
    public var permissionsDenied: Bool = false
    public var pulseIsRunning: Bool = false
    public var isSearching: Bool { sonosSystemDiscoverService.isSearching }
    public var lastKnownIP: String { sonosSystemDiscoverService.sonosStorageIP.sonosIP }
    public var state: String { sonosSystemDiscoverService.lastKnownState }

    @ObservationIgnored public var monitorTask: Task<Void, Error> = Task { }
    @ObservationIgnored public var sonosPulse: Task<Void, Error> = Task { }

    public var isRunning: Bool { !sonosPulse.isCancelled }
    @ObservationIgnored public var isEditing: Bool = false

    public init () {
        sonosPulse.cancel()
    }

    public var system: System?

    public var sorted: [GroupRoom] {
        get {
            let sorted = groups.sorted { $0.coordinatorRoom.name < $1.coordinatorRoom.name }
            return sorted
        } set {
            groups = newValue
        }
    }

    public var sortedRooms: [Room] {
        get {
            let sorted = rooms.sorted { $0.name < $1.name }
            return sorted
        } set {
            rooms = newValue
        }
    }

    public func updateGroups() async throws {
        let newGroup = try await getGroups(useCache: true)
        system = try await findSystem(useCache: true)
        if !newGroup.isEmpty && Set(newGroup) != Set(self.groups) {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
            self.zones = OrderedDictionary(uniqueKeys: newGroup.map(\.coordinatorID), values: newGroup)
        }
    }

    public func group(with id: String) -> GroupRoom? {
        sorted.first(where: { $0.coordinatorID == id})
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
                    if isEditing {
                        try? await Task.sleep(for: .milliseconds(500))
                        continue
                    }
                    // MARK: Update room volumes
                    if selectedGroup != nil {
                        try? await Task.sleep(for: .milliseconds(500))
                    } else {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    try await load(useCache: useCache)
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
        var refreshGroup: Bool = false

        if !newGroup.isEmpty && Set(newGroup) != Set(self.groups) {
            await updateGroupsRooms(from: newGroup)
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
            refreshGroup = true
        }

        if let selectedGroup, !refreshGroup {
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
            await updateGroupsRooms(from: [roomGroup])
            await updateGroupCheckTVMode(from: [roomGroup])

            guard !isEditing else { return }

            switch await playbackInfo {
            case .playing:
                roomGroup.coordinatorRoom.isPlaying = true
            case .paused:
                roomGroup.coordinatorRoom.isPlaying = false
            default:
                break
            }

            if let updateGroupVolume = try? await groupVolume, !roomGroup.isEditingVolume {
                roomGroup.groupVolume = updateGroupVolume
            }

            guard let track = await track else {
                ArtworkManager.shared.removeArtwork(coordinatorRoom: roomGroup.nameWithCount)
                roomGroup.coordinatorRoom.track = .empty
                return
            }

            let previousArtwork = roomGroup.coordinatorRoom.track.artworkURL
            if previousArtwork != nil {
                roomGroup.coordinatorRoom.track.artworkURL = previousArtwork
            }

            guard let artworkURL = await self.getArtwork(from: track, size: 200) else {
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
        await updateGroupsRooms(from: groups)
        await updateGroupCheckTVMode(from: groups)
        await updateGroupMuteState(for: groups)
    }

    @MainActor
    public func fetch(useCache: Bool) async throws {
        let newGroup = try await getGroups(useCache: useCache)
        var refreshGroup: Bool = false

        if !newGroup.isEmpty && Set(newGroup) != Set(self.groups) {
            await updateGroupsRooms(from: newGroup)
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
            refreshGroup = true
        }
        if let selectedGroup, !refreshGroup {
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

            let fetchedTrack = await track

            switch await playbackInfo {
            case .playing:
                roomGroup.coordinatorRoom.isPlaying = true
            case .paused:
                roomGroup.coordinatorRoom.isPlaying = false
            default:
                break
            }

            let updateGroupVolume = try await groupVolume
            if !roomGroup.isEditingVolume {
                roomGroup.groupVolume = updateGroupVolume
            }
            guard let fetchedTrack else {
                roomGroup.coordinatorRoom.track = .empty
                ArtworkManager.shared.removeArtwork(coordinatorRoom: roomGroup.nameWithCount)
                return
            }
            roomGroup.coordinatorRoom.track = fetchedTrack

            await updateGroupCheckTVMode(from: [groups[groupIndex]])
            await updateGroupsRooms(from: [groups[groupIndex]])


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
        await updateGroupsRooms(from: groups)
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

    public func updateGroups(from groups: [GroupRoom]) async throws {
        await withDiscardingTaskGroup { group in
            for roomGroup in groups {
                group.addTask{
                    async let track = self.getTrack(ip: roomGroup.coordinatorRoom.ip)
                    async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
                    async let groupVolume = self.getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
                    async let playMode = self.playMode(ip: roomGroup.coordinatorRoom.ip)

                    guard let awaitedTrack = await track else {
                        if roomGroup.coordinatorRoom.track != .empty {
                            roomGroup.coordinatorRoom.track = .empty
                        }
                        if let groupVolumeAwaited = try? await groupVolume, !roomGroup.isEditingVolume {
                            roomGroup.groupVolume = groupVolumeAwaited
                        }
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

                    switch await playbackInfo {
                    case .playing:
                        roomGroup.coordinatorRoom.isPlaying = true
                    case .paused:
                        roomGroup.coordinatorRoom.isPlaying = false
                    default:
                        break
                    }

                    if let groupVolumeAwaited = try? await groupVolume, !roomGroup.isEditingVolume {
                        roomGroup.groupVolume = groupVolumeAwaited
                    }

                    roomGroup.playMode = await playMode

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

                }
            }
        }
    }

    @MainActor
    public func updateGroupsRooms(from roomGroups: [GroupRoom]) async {
        await withDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                for room in roomGroup.rooms {
                    group.addTask {  [weak self] in
                        guard let self else { return }
                        if let volume = try? await getVolume(ip: room.ip), !room.isEditingVolume {
                            room.volume = volume
                        }
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
                group.addTask { [weak self] in
                    guard let self else { return }
                    let isTVMode = await self.isTVMode(ip: roomGroup.coordinatorRoom.ip)
                    roomGroup.tvMode = isTVMode

                    if isTVMode {
                        roomGroup.tvSettings = try? await getTVSettings(ip: roomGroup.coordinatorRoom.ip)
                    }
//
//                    // MARK: Make Screenshot Mock Mode
//                    if roomGroup.coordinatorRoom.name == "Theater" {
//                        roomGroup.tvMode = true
//                        roomGroup.tvSettings = try? await getTVSettings(ip: roomGroup.coordinatorRoom.ip)
//                        roomGroup.tvSettings?.audioInputFormat = .dolbyAtmosTrueHD
//                    }
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

                    if let groupVolumeAwaited = try? await groupVolume, !roomGroup.isEditingVolume {
                        roomGroup.groupVolume = groupVolumeAwaited
                    }
                    
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
        let groups = try await api.getGroups(ipAddress: ip)
        return groups
    }

    @MainActor
    public func findSystem(useCache: Bool) async throws -> System? {
        let IP = try await sonosSystemDiscoverService.getFirstIP(useCache: useCache)
        let system = try await api.system(for: IP)
        return system
    }

    public func getGroups(with ip: String) async throws -> [GroupRoom] {
        let groups = try await api.getGroups(ipAddress: ip)
        return groups
    }

    public func group(rooms: [Room], to coordinatorID: String) async {
        // MARK: Only group new rooms
        let nonCoordinatorRooms = rooms.filter{ $0.id != coordinatorID }
        for room in nonCoordinatorRooms {
            await api.group(IP: room.ip, to: coordinatorID)
        }
    }

    public func smartGroup(rooms: [Room], to group: GroupRoom) async {
        // MARK: Only group new rooms
        let rooms = rooms.filter { $0.id != group.coordinatorID }
        let nonCoordinatorRooms = group.rooms.filter { $0.id != group.coordinatorID }
        let changes = rooms.difference(from: nonCoordinatorRooms)

        if rooms.isEmpty {
            for room in nonCoordinatorRooms {
                await api.ungroup(IP: room.ip)
            }
            return
        }

        for change in changes {
            switch change {
            case let .insert(_, element, _):
                await api.group(IP: element.ip, to: group.coordinatorID)
            case let .remove(_, element, _):
                await api.ungroup(IP: element.ip)
            }
        }
    }

    /// Ungroup all rooms
    /// - Parameter group:
    public func ungroup(group: GroupRoom) async {
        await api.ungroup(IP: group.ip)
    }

    public func setDeviceVolume(ip: String, volume: Int) async {
        await api.setVolume(ipAddress: ip, volume: volume)
    }

    public func setRelativeVolume(ip: String, volume: Int) async {
        await api.setRelativeVolume(ipAddress: ip, volume: volume)
    }

    @MainActor
    public func setGroupMute(group: GroupRoom, mute: Bool) async {
        group.isMuted = mute
        await api.setGroupMute(IP: group.coordinatorRoom.ip, mute: mute)
    }

    public func setGroupVolume(ip: String, volume: Int) async {
        await api.setGroupVolume(ipAddress: ip, volume: volume)
    }

    public func setRelativeGroupVolume(ip: String, volume: Int) async {
        await api.setRelativeGroupVolume(ipAddress: ip, volume: volume)
    }

    public func snapShotGroup(ip: String) async {
        await api.snapshotGroupVolume(ipAddress: ip)
    }

    public func getTrack(ip: String) async -> Track? {
        await api.getCurrentTrack(ipAddress: ip)
    }

    @MainActor
    public func getArtwork(from track: Track, size: Int = 500) async -> URL? {
        switch track.musicService  {
        case .apple:
            guard let artworkString = await musicSearch.appleLookup(id: track.trackID)?.artworkURL(with: "\(size)"), let url = URL(string: artworkString) else { return track.sonosAlbumArtURL }
            return url
        case .spotify:
            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return nil }
            if size == 100, let image = spotifyTrack.album.images.sorted(by: { $0.height ?? 0 < $1.height ?? 0 } ).first {
                guard let url = URL(string: image.url) else { return nil }
                return url
            }

            if size == 200, spotifyTrack.album.images.count > 2 {
                let image = spotifyTrack.album.images[1]
                guard let url = URL(string: image.url) else { return nil }
                return url
            }

            guard let artworkString = spotifyTrack.album.images.first?.url, let url = URL(string: artworkString) else { return track.sonosAlbumArtURL }
            return url
        case .airplay, .unknown:
            return track.sonosAlbumArtURL
            // MARK: Delete
//            let searchResults = await musicSearch.search(song: track.name, artist: track.artist)
//            let found = searchResults.first { result in
//                result.artistName == track.artist &&
//                (result.trackName == track.name || result.trackCensoredName == track.name)
//            }
//            guard let artworkString = found?.artworkURL(with: "\(size)"), let url = URL(string: artworkString) else { return track.sonosAlbumArtURL }
//            return url
        }
    }

    public func getArtwork(from content: MediaContent, size: Int = 500) async -> URL? {
        guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
        
        if size == 100, let image = spotifyTrack.album.images.sorted(by: { $0.height ?? 0 < $1.height ?? 0 } ).first {
            guard let url = URL(string: image.url) else { return nil }
            return url
        }

        if size == 200, spotifyTrack.album.images.count > 2 {
            let image = spotifyTrack.album.images[1]
            guard let url = URL(string: image.url) else { return nil }
            return url
        }

        guard let artworkString = spotifyTrack.album.images.first?.url, let url = URL(string: artworkString) else { return nil }
        return url
    }

    public func getContent(from url: URL) async -> PlayableContent? {
        guard let content = api.parse(url: url) else { return nil }
        switch content.type {
        case .playlist:
            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
            return PlayableContent(title: playlist.name, subtitle: playlist.owner.displayName, artwork: URL(string: playlist.images.first?.url ?? ""), content: content)
        case .track:
            guard let track = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
            return PlayableContent(title: track.name, subtitle: track.artists.first?.name ?? "", artwork: URL(string: track.album.images.first?.url ?? ""), content: content)
        case .album:
            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id) else { return nil }
            return PlayableContent(title: album.name, subtitle: album.artists.first?.name ?? "", artwork: URL(string: album.images.first?.url ?? ""), content: content)
        default:
            break
        }
        return nil
    }

    public func getContent(from content: MediaContent) async -> PlayableContent? {
        switch content.type {
        case .playlist:
            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
            return PlayableContent(title: playlist.name, subtitle: playlist.owner.displayName, artwork: URL(string: playlist.images.first?.url ?? ""), content: content)
        case .track:
            guard let track = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
            return PlayableContent(title: track.name, subtitle: track.artists.first?.name ?? "", artwork: URL(string: track.album.images.first?.url ?? ""), content: content)
        case .album:
            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id) else { return nil }
            return PlayableContent(title: album.name, subtitle: album.artists.first?.name ?? "", artwork: URL(string: album.images.first?.url ?? ""), content: content)
        default:
            break
        }
        return nil
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

        await api.pause(ipAddress: ip)
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
        await api.play(ipAddress: ip)
    }

    public func next(ip: String) async {
        await api.next(ipAddress: ip)
    }

    public func previous(ip: String) async {
        await api.previous(ipAddress: ip)
    }

    public func isMuted(for group: GroupRoom) async -> Bool {
        await api.getGroupMute(IP: group.coordinatorRoom.ip)
    }
    
    public func getVolume(ip: String) async throws -> Double {
       try await api.getVolume(ipAddress: ip)
    }

    public func getGroupVolume(ip: String) async throws -> Double {
        try await api.getGroupVolume(ipAddress: ip)
    }

    public func getPlaybackInfo(ip: String) async -> PlaybackStatus {
        await api.isPlaying(ipAddress: ip)
    }

    public func getCurrentTransportActions(ip: String) async -> AvailableActions? {
        await api.getCurrentTransportActions(IP: ip)
    }

    public func playMode(ip: String) async -> PlayMode {
        await api.playMode(ip)
    }

    public func setPlayMode(_ IP: String, mode: PlayMode) async {
        await api.setPlayMode(IP, playMode: mode)
    }

    public func isTVMode(ip: String) async -> Bool {
       await api.mediaInfo(ipAddress: ip)
    }

    public func getTVSettings(ip: String) async throws -> TVSettings {
        let dialogLevel = try await api.getDialogLevel(IP: ip)
        let nightMode = try await api.getNightMode(IP: ip)
        let audioInputFormat = try await api.getAudioInputFormat(IP: ip)
        return TVSettings(nightMode: nightMode, dialogLevel: dialogLevel, audioInputFormat: audioInputFormat)
    }

    public func setDialogLevel(_ IP: String, enabled: Bool) async throws {
        try await api.setDialogLevel(IP: IP, enabled: enabled)
    }

    public func setNightMode(_ IP: String, enabled: Bool) async throws {
        try await api.setNightMode(IP: IP, enabled: enabled)
    }

    public func togglePlayback(ip: String) async {
        let playback =  await api.isPlaying(ipAddress: ip)
        switch playback {
        case .playing:
            await api.pause(ipAddress: ip)
        case .paused, .transitioning:
            await api.play(ipAddress: ip)
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

    public func runScene(_ scene: SonosScene) async throws {
        let playlistAction = { [weak self] in
            guard let self else { return }
            guard let roomID = scene.rooms.first?.id, let playableContentID = scene.playableContent?.content.id else { return }
            guard let group = await getGroupCoordinatorWithRoom(roomID: roomID) else { return }
            //    https://open.spotify.com/playlist/37i9dQZEVXcTv12cCWsQJf
            await queueSpotifyPlaylist(id: playableContentID, group: group)
        }

        let rooms = scene.rooms[1...].map { Room(id: $0.id, ip: $0.ip, name: $0.name)}
        for room in scene.rooms {
            await setDeviceVolume(ip: room.ip, volume: Int(room.volume))
        }
        
        if rooms.isEmpty {
            await api.ungroup(IP: scene.rooms.first!.ip)
            await playlistAction()
            return
        }

        await group(rooms: rooms, to: scene.rooms.first!.id)
        try? await Task.sleep(for: .milliseconds(300))
        guard let groupIP = scene.rooms.first?.ip else { return }
        await snapShotGroup(ip: groupIP)
        await playlistAction()
    }

    public func seek(trackNumber: Int, on group: GroupRoom) async {
        await api.setAVTransport(IP: group.coordinatorRoom.ip, ID: group.coordinatorID)
        await api.seek(trackNumber: trackNumber, IP: group.coordinatorRoom.ip)
    }

    public func seek(to time: TimeInterval, on group: GroupRoom) async {
        await api.seek(to: time, IP: group.coordinatorRoom.ip)
    }

    public func queue(song: String, on group: GroupRoom, position: QueuePosition = .now) async {
        await api.queue(song: song, IP: group.ip, position: position)

        if position == .now {
            await seek(trackNumber: group.coordinatorRoom.track.position + 1, on: group)
        }
    }

    public func queueSpotifyPlaylist(id: String, group: GroupRoom) async {
        await api.removeAllTrackFromQueue(IP: group.ip)
        await api.queueSpotifyPlaylist(ID: id, IP: group.ip)
        await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
    }

    public func queueSpotifyTrack(id: String, group: GroupRoom, position: QueuePosition = .now) async {
        await api.queueSpotifyTrack(ID: id, IP: group.coordinatorRoom.ip, position: position)

        if position == .now {
            await seek(trackNumber: group.coordinatorRoom.track.position + 1, on: group)
        }
    }

    public func queueSpotifyAlbum(id: String, group: GroupRoom, position: QueuePosition = .now) async {
        await api.queueSpotifyAlbum(ID: id, IP: group.coordinatorRoom.ip)

        if position == .now {
            await seek(trackNumber: group.coordinatorRoom.track.position + 1, on: group)
        }
    }

    // MARK: TODO add queueing for Apple Music
    public func queue(url: URL, group: GroupRoom, position: QueuePosition = .now) async {
        guard let content = api.parse(url: url) else {
            // Throw
            return
        }
        switch content.type {
        case .album:
            if content.service == .spotify {
                await queueSpotifyAlbum(id: content.id, group: group, position: position)
            }
        case .playlist:
            await api.removeAllTrackFromQueue(IP: group.ip)
            await api.queueSpotifyPlaylist(ID: content.id, IP: group.ip)
        case .artist:
            break
        case .track:
            if content.service == .spotify {
                await api.queueSpotifyTrack(ID: content.id, IP: group.ip, position: position)
            }
            if content.service == .apple {
                await api.queue(song: content.id, IP: group.ip, position: position)
            }
        }

        if position == .now {
            await seek(trackNumber: group.coordinatorRoom.track.position + 1, on: group)
        }
    }

    public func queue(content: MediaContent, group: GroupRoom, position: QueuePosition = .now) async {
        switch content.type {
        case .album:
            if content.service == .spotify {
                await queueSpotifyAlbum(id: content.id, group: group, position: position)
            }
        case .playlist:
            await api.removeAllTrackFromQueue(IP: group.ip)
            await api.queueSpotifyPlaylist(ID: content.id, IP: group.ip)
        case .artist:
            break
        case .track:
            if content.service == .spotify {
                await api.queueSpotifyTrack(ID: content.id, IP: group.ip, position: position)
            }
            if content.service == .apple {
                await api.queue(song: content.id, IP: group.ip, position: position)
            }
        }

        if position == .now {
            await seek(trackNumber: group.coordinatorRoom.track.position + 1, on: group)
        }
    }


    public func getQueue(ip: String) async -> [Track] {
        await api.getQueue(IP: ip)
    }

    public func clearQueue(_ IP: String) async throws {
        await api.removeAllTrackFromQueue(IP: IP)
    }

    public func removeTrackFromQueue(_ IP: String, index: Int) async throws {
        await api.removeTrackFromQueue(IP: IP, index: index)
    }

    public func reorderQueue(_ group: GroupRoom, from: Int, to: Int) async throws {
        await api.reorderQueue(group: group, from: from, to: to)
    }

    public func getGroupCoordinatorWithRoom(roomID: String) async -> GroupRoom? {
        do {
            let groups = try await getGroups(useCache: true)
            let group = groups.first { group in
                group.rooms.contains { room in
                    room.id == roomID
                }
            }
            return group
        } catch {
            print(error)
            return nil
        }
    }

    public func getHouseID() async -> String {
        guard let ip = groups.first?.ip else { return "" }
        return await api.getHouseHoldID(for: ip)
    }
}



