import Foundation
import OrderedCollections
import MusicSearchKit
import Observation
import SwiftUI
import MusicKit

@Observable
public class SonosSystemState {
    public var notFound: Bool = false
    @ObservationIgnored var systemNotFound: Bool = false {
        didSet {
            if oldValue != systemNotFound {
                notFound = systemNotFound
            }
        }
    }

    public var permissionDenied: Bool = false
    @ObservationIgnored var systemPermissionDenied: Bool = false {
        didSet {
            if oldValue != systemPermissionDenied {
                permissionDenied = systemPermissionDenied
            }
        }
    }
}

@Observable
public final class SonosService {
    @ObservationIgnored public static var shared = SonosService()

    public var ID: String? = nil
    public var groups: [GroupRoom] = []
    public var favorites: FavoritesList?
    public var zones: OrderedDictionary<String, GroupRoom> = [:]

    public var rooms: [Room] = []
    public var selectedGroup: GroupRoom? = nil

    @ObservationIgnored public lazy var networkMonitorService = NetworkMonitorService()
    @ObservationIgnored private lazy var sonosSystemDiscoverService = SonosSystemDiscoverService()
    @ObservationIgnored private lazy var api = SonosAPI()
    @ObservationIgnored private lazy var musicSearch = MusicSearchService()
    @ObservationIgnored private var isGroupingTask: Task<Void, Error> = Task { }

    public var systemState = SonosSystemState()
    public var isSearching: Bool { sonosSystemDiscoverService.isSearching }
    public var lastKnownIP: String { sonosSystemDiscoverService.sonosStorageIP.sonosIP }
    public var state: String { sonosSystemDiscoverService.lastKnownState }
    public var parserError: String?

    @ObservationIgnored public var monitorTask: Task<Void, Error> = Task { }
    @ObservationIgnored public var sonosPulse: Task<Void, Error> = Task { }
    @ObservationIgnored public var watcher: Task<Void, Error> = Task { }
    @ObservationIgnored public var isEditing: Bool = false
    @ObservationIgnored public var isGrouping: Bool = false

    public var isRunning: Bool { !sonosPulse.isCancelled }
    public var groupsChanged: (([GroupRoom]) -> ()) = { _ in }

    public init () {
        sonosPulse.cancel()
    }

    public var system: System?

    public var primaryHouseID: String? { sonosSystemDiscoverService.houseHoldIDs.first }
    public var houseIDs: Set<String> { sonosSystemDiscoverService.houseHoldIDs }

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

        // MARK: Update Battery Info
        for updateGroup in newGroup.filter({ $0.coordinatorRoom.battery != nil }) {
            guard let index = groups.firstIndex(of: updateGroup) else { continue }
            groups[index].coordinatorRoom.battery = updateGroup.coordinatorRoom.battery
        }

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

        self.watcher = Task { [weak self] in
            guard let self else { return }
            repeat {
                if isEditing {
                    try? await Task.sleep(for: .milliseconds(500))
                    continue
                }
                // MARK: Update room volumes
                if let selectedGroup {
                    try? await Task.sleep(for: .milliseconds(1000))
                    let nonSelectedGroup = groups.filter { $0 != selectedGroup }
                    try await updateGroups(from: nonSelectedGroup)
                    await updateGroupCheckTVMode(from: nonSelectedGroup)
                    await updateGroupMuteState(for: nonSelectedGroup)
                    await updateGroupsRooms(from: nonSelectedGroup)
                } else {
                    try? await Task.sleep(for: .milliseconds(1000))
                }
            } while (!watcher.isCancelled)
        }

        self.sonosPulse = Task { [weak self] in
            guard let self else { return }
            var useCache = useCache
            var retry = retry
            repeat {
                groupsChanged(sorted)
                do {
                    systemState.systemNotFound = false
                    systemState.systemPermissionDenied = false
                    if isEditing {
                        try? await Task.sleep(for: .milliseconds(500))
                        continue
                    }
                    // MARK: Update room volumes
                    try? await Task.sleep(for: .milliseconds(selectedGroup != nil ? 500 : 800))
                    try await load(useCache: useCache)

                    useCache = true
                } catch SonosServiceError.permissionDenied {
                    print("Permission")
                    systemState.systemPermissionDenied = true
                    sonosPulse.cancel()
                } catch SonosServiceError.parseError(let xml) {
                    parserError = xml
                    guard retry else {
                        print("System not found")
                        systemState.systemNotFound = true
                        sonosPulse.cancel()
                        return
                    }
                    // MARK: Invalidate Cache
                    useCache = false
                    retry = false
                }  catch SonosServiceError.sonosSystemNotFound {
                    guard retry else {
                        print("System not found")
                        systemState.systemNotFound = true
                        sonosPulse.cancel()
                        return
                    }
                    // MARK: Invalidate Cache
                    useCache = false
                    retry = false
                } catch {
                    print(error)
                    sonosPulse.cancel()
                    print(#function, error)
                }
            } while (!sonosPulse.isCancelled)
        }
    }

    @MainActor
    public func monitorWatch(retry: Bool = true, duration: Duration = .seconds(1.5), useCache: Bool) {
        if isRunning { return }
        print("Monitoring!")
        self.sonosPulse = Task { [weak self] in
            guard let self else { return }
            var useCache = useCache

            repeat {
                do {
                    systemState.systemNotFound = false
                    systemState.systemPermissionDenied = false
                    try await fetch(useCache: useCache)
                    try? await Task.sleep(for: duration) // exception thrown when cancelled by SwiftUI when this view disappears.
                    useCache = true
                } catch SonosServiceError.permissionDenied {
                    print("Permision")
                    systemState.systemNotFound = true
                    sonosPulse.cancel()
                }
                catch SonosServiceError.sonosSystemNotFound {
                    print("System not found")
                    systemState.systemNotFound = true
                    // MARK: Invalidate Cache
                    useCache = false
                } catch {
                    print(error)
                    systemState.systemPermissionDenied = true
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

        // MARK: Update Battery Info And Other Room Information
        for updateGroup in newGroup {
            guard let index = groups.firstIndex(of: updateGroup) else { continue }
            groups[index].coordinatorRoom.ethernetEnabled = updateGroup.coordinatorRoom.ethernetEnabled
            groups[index].coordinatorRoom.micEnabled = updateGroup.coordinatorRoom.micEnabled
            groups[index].coordinatorRoom.battery = updateGroup.coordinatorRoom.battery
            if groups[index].coordinatorRoom.info == nil, updateGroup.coordinatorRoom.state == .active {
                print("Update device Info")
                groups[index].coordinatorRoom.info = await api.deviceInfo(IP: updateGroup.coordinatorRoom.ip)
            }
        }

        if !newGroup.isEmpty, Set(newGroup) != Set(groups), !isGrouping {
            await updateGroupsRooms(from: newGroup)
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
            refreshGroup = true
            print("Refreshed")
            print("NewGroup \(newGroup.count), Old \(groups.count)")
            print("Set NewGroup \(Set(newGroup).count), Old \(Set(groups).count)")

            print(isGrouping)
        }

        await wakeSleepingRooms(rooms: rooms)

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
            if selectedGroup.coordinatorRoom.state != .active { return }

            let roomGroup = groups[groupIndex]
            if roomGroup != selectedGroup {
                self.selectedGroup = roomGroup
            }
            async let track = self.getTrack(ip: roomGroup.coordinatorRoom.ip)
            async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
            async let groupVolume = self.getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
            async let playMode = self.playMode(ip: roomGroup.coordinatorRoom.ip)
            async let availableActions = self.getCurrentTransportActions(ip: roomGroup.ip)
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

            if let awaitedActions = await availableActions {
                roomGroup.availableActions = awaitedActions
            }

            await updateGroupsRooms(from: [roomGroup])
            await updateGroupMuteState(for: [roomGroup])

            guard let awaitedTrack = await track else {
                return
            }

            if awaitedTrack == .empty {
                if roomGroup.coordinatorRoom.track != .empty {
                    ArtworkManager.shared.removeArtwork(coordinatorRoom: roomGroup.nameWithCount)
                    roomGroup.coordinatorRoom.track = .empty
                    roomGroup.coordinatorRoom.track.downloadedArtworkURL = nil
                    roomGroup.coordinatorRoom.track.sonosAlbumArtURL = nil
                }
                return
            }

            let previousArtwork = roomGroup.coordinatorRoom.track.artworkURL
            if previousArtwork != nil {
                roomGroup.coordinatorRoom.track.downloadedArtworkURL = previousArtwork
            }

            guard let (trackMetadata, artworkURL) = await self.getTrackInformation(from: awaitedTrack) else {
                if roomGroup.coordinatorRoom.track != awaitedTrack {
                    roomGroup.coordinatorRoom.track = awaitedTrack
                } else {
                    roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                }
                return
            }

            roomGroup.playMode = await playMode

            awaitedTrack.downloadedArtworkURL = roomGroup.coordinatorRoom.track.artworkURL
            awaitedTrack.metadata = trackMetadata

            if artworkURL != awaitedTrack.artworkURL {
                roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
            }

            if roomGroup.coordinatorRoom.track != awaitedTrack {
                roomGroup.coordinatorRoom.track = awaitedTrack
                roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
            } else {
                roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
            }
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

        // MARK: Update Battery Info
        for updateGroup in newGroup.filter({ $0.coordinatorRoom.battery != nil }) {
            guard let index = groups.firstIndex(of: updateGroup) else { continue }
            groups[index].coordinatorRoom.battery = updateGroup.coordinatorRoom.battery
        }

        if !newGroup.isEmpty && Set(newGroup) != Set(self.groups) {
            await updateGroupsRooms(from: newGroup)
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
            refreshGroup = true
        }

        await wakeSleepingRooms(rooms: rooms)

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

    @MainActor
    public func updateGroups(from groups: [GroupRoom]) async throws {
        await withDiscardingTaskGroup { group in
            for roomGroup in groups {
                group.addTask { [weak self] in
                    guard let self else { return }
                    // MARK: Sleeping or Off
                    if roomGroup.coordinatorRoom.state != .active { return }

                    async let track = getTrack(ip: roomGroup.coordinatorRoom.ip)
                    async let playbackInfo = getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
                    async let groupVolume = getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
                    async let playMode = playMode(ip: roomGroup.coordinatorRoom.ip)
                    async let availableActions = getCurrentTransportActions(ip: roomGroup.ip)

                    if let groupVolumeAwaited = try? await groupVolume, !roomGroup.isEditingVolume {
                        roomGroup.groupVolume = groupVolumeAwaited
                    }

                    guard let awaitedTrack = await track else {
                        return
                    }

                    if awaitedTrack == .empty {
                        if roomGroup.coordinatorRoom.track != .empty {
                            ArtworkManager.shared.removeArtwork(coordinatorRoom: roomGroup.nameWithCount)
                            roomGroup.coordinatorRoom.track = .empty
                            roomGroup.coordinatorRoom.track.downloadedArtworkURL = nil
                            roomGroup.coordinatorRoom.track.sonosAlbumArtURL = nil
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

                    if let awaitedActions = await availableActions {
                        roomGroup.availableActions = awaitedActions
                    }

                    guard let (trackMetadata, artworkURL) = await getTrackInformation(from: awaitedTrack) else {
                        if roomGroup.coordinatorRoom.track != awaitedTrack {
                            roomGroup.coordinatorRoom.track = awaitedTrack
                        } else {
                            roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                        }
                        print("Failed")
                        return
                    }

                    roomGroup.playMode = await playMode
                    awaitedTrack.downloadedArtworkURL = artworkURL
                    awaitedTrack.metadata = trackMetadata

                    if roomGroup.coordinatorRoom.track != awaitedTrack {
                        roomGroup.coordinatorRoom.track = awaitedTrack
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
                    group.addTask { [weak self] in
                        if room.state != .active { return }
                        guard let self else { return }
                        if let volume = try? await getVolume(ip: room.ip), !room.isEditingVolume {
                            room.volume = volume
                        }
                    }

                    group.addTask { [weak self] in
                        if room.state != .active { return }
                        guard let self else { return }
                        if let isMuted = await api.getRoomMute(IP: room.ip) {
                            room.isMuted = isMuted
                        }
                    }

                    // MARK: Check Alarm
                    group.addTask { [weak self] in
                        if room.state != .active { return }
                        guard let self else { return }
                        let isRunningAlarm = await api.getRunningAlarm(IP: room.ip)
                        if room.alarmRunning != isRunningAlarm {
                            room.alarmRunning = isRunningAlarm
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
                group.addTask {
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
                if roomGroup.coordinatorRoom.state != .active { return }

                group.addTask { [weak self] in
                    guard let self else { return }
                    // MARK: Sleeping or Off
                    // MARK: Theater Mock
                    //                    if roomGroup.coordinatorRoom.name == "Theater" {
                    //                        roomGroup.coordinatorRoom.track.TVMode = true
                    //                        roomGroup.tvSettings = try? await getTVSettings(ip: roomGroup.coordinatorRoom.ip)
                    //                        roomGroup.tvSettings?.audioInputFormat = .dolbyAtmosTrueHD
                    //                        return
                    //                    }
                    if let playbackService = await playbackService(ip: roomGroup.ip) {
                        roomGroup.playbackService = playbackService
                    }

                    if roomGroup.playbackService == .tv {
                        roomGroup.tvSettings = try? await getTVSettings(ip: roomGroup.ip)
                    } else {
                        roomGroup.tvSettings = nil
                    }
                }
            }
        }
    }

    @MainActor
    public func updateGroupMuteState(for roomGroups: [GroupRoom]) async {
        await withDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                group.addTask {
                    if roomGroup.coordinatorRoom.state == .active, let isMuted = await self.isMuted(for: roomGroup) {
                        roomGroup.isMuted = isMuted
                    }
                }
            }
        }
    }

    @MainActor
    public func wakeSleepingRooms(rooms: [Room]) async {
        await withDiscardingTaskGroup { taskGroup in
            for room in rooms {
                taskGroup.addTask { [weak self] in
                    if let macAddress = room.macAddress, room.state == .sleeping {
                        self?.sonosSystemDiscoverService.sendWakeOnLANPacket(macAddress: macAddress)
                    }
                }
            }
        }
    }

    @MainActor
    func updateGroupsWatch(from roomGroups: [GroupRoom]) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                group.addTask {
                    // MARK: Sleeping
                    if roomGroup.coordinatorRoom.state != .active { return }

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

                    guard let awaitedTrack = await track else { return }

                    guard let artworkURL = await self.getArtwork(from: awaitedTrack, size: 200) else {
                        if roomGroup.coordinatorRoom.track != awaitedTrack {
                            roomGroup.coordinatorRoom.track = awaitedTrack
                        } else {
                            roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                        }
                        return
                    }

                    awaitedTrack.downloadedArtworkURL = roomGroup.coordinatorRoom.track.downloadedArtworkURL

                    if artworkURL != awaitedTrack.artworkURL {
                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                    }

                    if roomGroup.coordinatorRoom.track != awaitedTrack {
                        roomGroup.coordinatorRoom.track = awaitedTrack
                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                    } else {
                        roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                    }
                    return
                }
            }
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

    public func smartGroup(rooms: [Room], oldRooms: [Room], to group: GroupRoom) async -> String? {
        var newCoordinatorID: String? = nil

        isGrouping = true
        let newRooms = Set(rooms)
        let oldRoomsSet = Set(oldRooms)

        // Determine the rooms that have been added
        let addedRooms = newRooms.subtracting(oldRoomsSet)

        for room in addedRooms {
            print("Added room: \(room)")
            // MARK: Remove Rooms
            for group in groups {
                group.rooms.removeAll(where: { $0.id == room.id })
            }

            if let groupIndex = groups.firstIndex(where: { groupLooking in groupLooking.coordinatorID == group.coordinatorID }) {
                groups[groupIndex].rooms.append(room)
            }

            groups.removeAll(where: { group in group.coordinatorID == room.id })
            await api.group(IP: room.ip, to: group.coordinatorID)
        }

        // Determine the rooms that have been removed
        let removedRooms = oldRoomsSet.subtracting(newRooms)
        for room in removedRooms {
            print("Removed room: \(room)")
            let groupIndex = groups.firstIndex { groupResult in
                groupResult.coordinatorID == group.coordinatorID
            }

            if let groupIndex {
                groups[groupIndex].rooms.removeAll { roomResult in
                    roomResult.id == room.id
                }
                print(groups[groupIndex].rooms)

                // Address If Coordinator Room is changing
                if group.coordinatorID == room.id {
                    print("Removing Coordinator")
                    if let newCoordinatorRoom = groups[groupIndex].rooms.first {
                        groups[groupIndex].coordinatorRoom = newCoordinatorRoom
                        newCoordinatorID = newCoordinatorRoom.id
                    }
                }
            }

            groups.append(room.toGroup)
            await api.ungroup(IP: room.ip)
        }

        isGroupingTask.cancel()
        isGroupingTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            if Task.isCancelled { return }
            isGrouping = false
        }

        return newCoordinatorID
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

    @MainActor
    public func setRoomMute(room: Room, mute: Bool) async {
        room.isMuted = mute
        await api.setRoomMute(IP: room.ip, mute: mute)
    }

    public func setGroupVolume(ip: String, volume: Int) async {
        await api.setGroupVolume(IP: ip, volume: volume)
    }

    public func setRelativeGroupVolume(ip: String, volume: Int) async {
        await api.setRelativeGroupVolume(ipAddress: ip, volume: volume)
    }

    public func snapShotGroup(ip: String) async {
        await api.snapshotGroupVolume(ipAddress: ip)
    }

    public func getTrack(ip: String) async -> Track? {
        await api.getCurrentTrack(ipAddress: ip, prioritizedAlbumArtIP: prioritizedIP())
    }

    public func getArtwork(from track: Track, size: Int = 500) async -> URL? {
        switch track.musicService  {
        case .apple:
            guard let artworkString = await musicSearch.appleLookup(id: track.trackID)?.artworkURL(with: "\(size)"), let url = URL(string: artworkString) else { return nil }
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

            guard let artworkString = spotifyTrack.album.images.first?.url, let url = URL(string: artworkString) else { return nil }
            return url
        case .tidal:
            // TODO: Add back when production is enabled for Tidal
            return nil
//            guard let tidalTrack = await musicSearch.lookupTidalTrack(with: track.trackID) else { return nil }
//            return tidalTrack.artwork
        case .plex:
            print(track.artworkURL)
            print(track)
            
            return nil
        case .airplay, .unknown, .library:
            return nil
        }
    }

    // TODO: Change size to enum
    public func getTrackInformation(from track: Track, size: Int = 500) async -> (Track.Metadata?, URL?)? {
        switch track.musicService {
        case .spotify:
            var imageURL: URL?
            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return (nil, nil) }

            if size == 100, let image = spotifyTrack.album.images.sorted(by: { $0.height ?? 0 < $1.height ?? 0 } ).first {
                imageURL = URL(string: image.url)
            } else if size == 200, spotifyTrack.album.images.count > 2 {
                let image = spotifyTrack.album.images[1]
                imageURL = URL(string: image.url)
            } else if let artworkString = spotifyTrack.album.images.first?.url {
                imageURL = URL(string: artworkString)
            }

            return (Track.Metadata(ISRC: spotifyTrack.externalIds.isrc, openInURL: URL(string: spotifyTrack.externalUrls.spotify), contentType: .track), imageURL)
        case .apple:
            var imageURL: URL? = nil
            guard let appleTrack = await musicSearch.appleLookup(id: track.trackID) else { return (nil, nil) }
            imageURL = URL(string: appleTrack.artworkURL(with: "\(size)"))
            return (Track.Metadata(ISRC: nil, openInURL: URL(string: appleTrack.trackViewURL), contentType: .track), imageURL)
        case .tidal:
            guard let tidalTrack = await musicSearch.lookupTidalTrack(with: track.trackID) else { return (nil, nil) }
            return (Track.Metadata(ISRC: nil, openInURL: tidalTrack.content.location, contentType: .track), tidalTrack.artwork)
        case .unknown:
            if track.metadata?.contentType != .track { return (nil, nil) }
            guard let artworkString = await musicSearch.search(song: track.name, artist: track.artist, album: track.album).first?.artworkURL else { return (nil, nil) }
            return (Track.Metadata(ISRC: nil, openInURL: nil, contentType: .track), URL(string: artworkString))
        default:
            return (nil, nil)
        }
    }

    public func getArtwork(from content: MediaContent, size: Int = 500) async -> URL? {
        switch (content.type, content.service) {
        case (.album, .spotify):
            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id) else { return nil }
            return album.images.biggestImageURL
        case (.track, .spotify):
            guard let track = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
            return track.album.images.biggestImageURL
        case (.playlist, .spotify):
            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
            return playlist.images.biggestImageURL
        case (.track, .apple):
            guard let song: Song = try? await musicSearch.lookup(id: content.id) else { return nil }
            return song.artwork?.url(width: 500, height: 500)
        case (.album, .apple):
            guard let album: Album = try? await musicSearch.lookup(id: content.id) else { return nil }
            return album.artwork?.url(width: 500, height: 500)
        case (.playlist, .apple):
            guard let playlist: Playlist = try? await musicSearch.lookup(id: content.id) else { return nil }
            return playlist.artwork?.url(width: 500, height: 500)
        default:
            return nil
        }
    }

    public func getContent(from url: URL) async -> PlayableContent? {
        guard let content = api.parse(url: url) else { return nil }
        switch (content.type, content.service) {
        case (.album, .spotify):
            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id) else { return nil }
            return PlayableContent(title: album.name, subtitle: album.artists.first?.name ?? "", artwork: URL(string: album.images.first?.url ?? ""), content: content)
        case (.track, .spotify):
            guard let track = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
            return PlayableContent(title: track.name, subtitle: track.artists.first?.name ?? "", artwork: URL(string: track.album.images.first?.url ?? ""), content: content)
        case (.playlist, .spotify):
            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
            return PlayableContent(title: playlist.name, subtitle: playlist.owner.displayName, artwork: URL(string: playlist.images.first?.url ?? ""), content: content)
        case (.track, .apple):
            guard let song: Song = try? await musicSearch.lookup(id: content.id) else { return nil }
            return PlayableContent(title: song.title, subtitle: song.artistName, artwork: song.artwork?.url(width: 500, height: 500), content: content)
        case (.album, .apple):
            guard let album: Album = try? await musicSearch.lookup(id: content.id) else { return nil }
            return PlayableContent(title: album.title, subtitle: album.artistName, artwork: album.artwork?.url(width: 500, height: 500), content: content)
        case (.playlist, .apple):
            guard let playlist: Playlist = try? await musicSearch.lookup(id: content.id) else { return nil }
            return PlayableContent(title:   playlist.name, subtitle: playlist.curatorName ?? "", artwork: playlist.artwork?.url(width: 500, height: 500), content: content)
        default:
            return nil
        }
    }

    public func getContent(from content: MediaContent) async -> PlayableContent? {
        switch content.type {
        case .playlist:
            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
            return PlayableContent(title: playlist.name, subtitle: playlist.owner.displayName, artwork: URL(string: playlist.images.first?.url ?? ""), content: content)
        case .track:
            if content.service == .spotify {
                guard let track = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
                return PlayableContent(title: track.name, subtitle: track.artists.first?.name ?? "", artwork: URL(string: track.album.images.first?.url ?? ""), content: content)
            }

            if content.service == .apple {
                guard let track = await musicSearch.appleLookup(id: content.id) else { return nil }
                return PlayableContent(title: track.trackName, subtitle: track.artistName, artwork: URL(string: track.artworkURL), content: content)
            }
        case .album:
            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id) else { return nil }
            return PlayableContent(title: album.name, subtitle: album.artists.first?.name ?? "", artwork: URL(string: album.images.first?.url ?? ""), content: content)
        default:
            break
        }
        return nil
    }


    public func pause(ip: String) async {
        let groupIndex = groups.firstIndex { group in
            group.coordinatorRoom.ip == ip
        }

        if let groupIndex {
            for (index, _) in groups[groupIndex].rooms.enumerated() {
                groups[groupIndex].rooms[index].isPlaying = false
                groups[groupIndex].coordinatorRoom.isPlaying = false
            }
        }

        isEditing = true
        await api.pause(ipAddress: ip)
        try? await Task.sleep(for: .seconds(2))
        isEditing = false
    }

    public func play(ip: String) async {
        let groupIndex = groups.firstIndex { room in
            room.coordinatorRoom.ip == ip
        }

        if let groupIndex {
            for (index, _) in groups[groupIndex].rooms.enumerated() {
                groups[groupIndex].rooms[index].isPlaying = true
                groups[groupIndex].coordinatorRoom.isPlaying = true
            }
        }
        isEditing = true
        await api.play(ipAddress: ip)
        try? await Task.sleep(for: .seconds(2))
        isEditing = false
    }

    public func next(ip: String) async {
        await api.next(ipAddress: ip)
    }

    public func previous(ip: String) async {
        // TODO: Seek to beginning of track
        await api.previous(ipAddress: ip)
    }

    public func isMuted(for group: GroupRoom) async -> Bool? {
        await api.getGroupMute(IP: group.coordinatorRoom.ip)
    }

    public func isCrossfaded(for group: GroupRoom) async -> Bool? {
        await api.crossfade(IP: group.coordinatorRoom.ip)
    }

    public func setCrossfade(group: GroupRoom, enabled: Bool) async {
        group.isCrossfaded = enabled
        await api.setCrossfade(IP: group.coordinatorRoom.ip, enabled: enabled)
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

    public func sleepTimer(group: GroupRoom, duration: Duration) async {
        group.coordinatorRoom.sleepTimer = Date.now.addingTimeInterval(Double(duration.components.seconds))
        await api.setSleepTimer(IP: group.ip, duration: duration)
    }

    public func getSleepTimer(group: GroupRoom) async {
        group.coordinatorRoom.sleepTimer = await api.getSleepTimer(IP: group.ip)
    }

    public func stopSleepTimer(group: GroupRoom) async {
        await api.stopSleepTimer(IP: group.ip)
        group.coordinatorRoom.sleepTimer = nil
    }

    @MainActor
    public func playMode(ip: String) async -> PlayMode {
        await api.playMode(ip)
    }

    public func setPlayMode(_ IP: String, mode: PlayMode) async {
        await api.setPlayMode(IP, playMode: mode)
    }

    public func playbackService(ip: String) async -> PlaybackService? {
        await api.mediaInfo(ipAddress: ip)
    }

    public func getTVSettings(ip: String) async throws -> TVSettings {
        let audioInputFormat = try await api.getAudioInputFormat(IP: ip)
        let dialogLevel = try await api.getDialogLevel(IP: ip)
        let nightMode = try await api.getNightMode(IP: ip)
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
            guard let roomID = scene.rooms.first?.id, let playableContent = scene.playableContent else { return }
            guard let group = await getGroupCoordinatorWithRoom(roomID: roomID) else { return }
            await queue(playable: playableContent, group: group)
            await play(ip: group.ip)
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
        let queueActive = group.playbackService == .queue
        if !queueActive {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }
        await api.seek(trackNumber: trackNumber, IP: group.coordinatorRoom.ip)
    }

    public func getFavoriteList() async {
        guard let ip = prioritizedIP() else { return }
        self.favorites = await api.getFavorites(for: ip)
    }

    public func playFavorite(on group: GroupRoom, favoriteID: String) async {
        await api.playFavorite(on: group, favoriteID: favoriteID)
        await api.play(ipAddress: group.ip)
    }

    public func favoriteImageURL(favorite: Favorite) -> URL? {
        guard let ip = prioritizedIP() else { return nil }
        return api.favoriteArtwork(on: favorite, IP: ip)
    }

    public func deleteFavorite(on group: GroupRoom?, favoriteID: String) async {
        guard let foundGroup = groups.first else { return }
        await api.deleteFavorite(IP: group?.ip ?? foundGroup.ip, itemID: favoriteID)
    }

    public func seek(to time: TimeInterval, on group: GroupRoom) async {
        await api.seek(to: time, IP: group.coordinatorRoom.ip)
    }

    public func queueAppleSong(id: String, group: GroupRoom, position: QueuePosition = .now) async {
        let queueActive = group.playbackService == .queue

        if !queueActive {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }

        await api.queueAppleSong(id: id, IP: group.ip, position: position)

        if position == .now, queueActive {
            await next(ip: group.ip)
        }
    }

    public func queueAppleAlbum(id: String, group: GroupRoom, position: QueuePosition = .now) async {
        let queueActive = group.playbackService == .queue

        if !queueActive {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }

        await api.queueAppleAlbum(ID: id, IP: group.coordinatorRoom.ip, position: position)

        if position == .now, queueActive {
            await next(ip: group.ip)
        }
    }

    public func queueApplePlaylist(id: String, group: GroupRoom) async {
        await api.removeAllTrackFromQueue(IP: group.ip)
        await api.queueApplePlaylist(ID: id, IP: group.ip)
        await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
    }

    public func queueSpotifyPlaylist(id: String, group: GroupRoom) async {
        await api.removeAllTrackFromQueue(IP: group.ip)
        await api.queueSpotifyPlaylist(ID: id, IP: group.ip)
        if group.playbackService != .queue {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }
    }

    public func queueSpotifyArtistTopTracks(id: String, group: GroupRoom) async {
        if group.playbackService != .queue {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }
        await api.queueSpotifyArtistTopTracks(ID: id, IP: group.ip)
    }

    public func queueSpotifyArtistRadio(id: String, group: GroupRoom) async {
        if group.playbackService != .queue {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }
        await api.queueSpotifyArtistRadio(ID: id, IP: group.ip)
    }

    public func queueSpotifyTrack(id: String, group: GroupRoom, position: QueuePosition = .now) async {
        let queueActive = group.playbackService == .queue

        if !queueActive {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }

        await api.queueSpotifyTrack(ID: id, IP: group.coordinatorRoom.ip, position: position)
        if position == .now, queueActive {
            await next(ip: group.ip)
        }
    }

    public func queueSpotifyAlbum(id: String, group: GroupRoom, position: QueuePosition = .now) async {
        let queueActive = group.playbackService == .queue

        if !queueActive {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }
        await api.queueSpotifyAlbum(ID: id, IP: group.coordinatorRoom.ip, position: position)

        if position == .now, queueActive {
            await next(ip: group.ip)
        }
    }

    public func queuePlayable(playable: PlayableContent, group: GroupRoom, position: QueuePosition = .now, replaceQueue: Bool = false) async {
        if playable.content.type == .playlist {
            await api.removeAllTrackFromQueue(IP: group.ip)
        }

        let queueActive = group.playbackService == .queue

        if !queueActive {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }

        await api.queuePlayable(playableContent: playable, IP: group.coordinatorRoom.ip, position: position)

        if position == .now, queueActive, playable.content.type != .playlist {
            await next(ip: group.ip)
        }
    }

    // MARK: Library
    public func playLibraryItem(on group: GroupRoom, ID: String, position: QueuePosition = .now) async {
        let queueActive = group.playbackService == .queue

        if !queueActive {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }

        await api.queueLibraryItem(ID: ID, IP: group.ip, position: position)

        if position == .now, queueActive {
            await next(ip: group.ip)
        }
    }

    // MARK: TODO add queueing for Apple Music
    public func queue(url: URL, group: GroupRoom, position: QueuePosition = .now) async {
        guard let content = api.parse(url: url) else {
            // Throw
            // TODO: Add better error
            return
        }

        switch (content.type, content.service) {
        case (.album, .spotify):
            await queueSpotifyAlbum(id: content.id, group: group, position: position)
        case (.track, .spotify):
            await queueSpotifyTrack(id: content.id, group: group, position: position)
        case (.playlist, .spotify):
            await queueSpotifyPlaylist(id: content.id, group: group)
        case (.track, .apple):
            await queueAppleSong(id: content.id, group: group, position: position)
        case (.album, .apple):
            await queueAppleAlbum(id: content.id, group: group, position: position)
        case (.playlist, .apple):
            await queueApplePlaylist(id: content.id, group: group)
        case (.favorite, _):
            await playFavorite(on: group, favoriteID: content.id)
        default:
            return
        }
    }

    public func queue(playable: PlayableContent, group: GroupRoom, position: QueuePosition = .now) async {
        switch (playable.content.type, playable.content.service) {
        case (.track, .spotify):
            await queuePlayable(playable: playable, group: group, position: position)
        case (.album, .spotify):
            await queuePlayable(playable: playable, group: group, position: position)
        case (.artist, .spotify):
            await queueSpotifyArtistTopTracks(id: playable.content.id, group: group)
        case (.playlist, .spotify):
            await queuePlayable(playable: playable, group: group, position: position)
        case (.track, .apple):
            await queueAppleSong(id: playable.content.id, group: group, position: position)
        case (.album, .apple):
            await queueAppleAlbum(id: playable.content.id, group: group, position: position)
        case (.artist, .apple):
            break
        case (.playlist, .apple):
            await queueApplePlaylist(id: playable.content.id, group: group)
        case (.favorite, _):
            await playFavorite(on: group, favoriteID: playable.content.id)
        case (_, .library):
            await playLibraryItem(on: group, ID: playable.content.id, position: position)
        case (.track, .plex):
            await queuePlayable(playable: playable, group: group, position: position)
            // MARK: - Tidal
        case (_, .tidal):
            await queuePlayable(playable: playable, group: group, position: position)
        default:
            break
        }
    }

    public func getQueue(ip: String) async -> [Track] {
        await api.getQueue(IP: ip, prioritizedAlbumArtIP: prioritizedIP() )
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

    public func getHouseID() async -> String? {
        // MARK: Update use faster Sonos Devices if Available
        guard let ip = prioritizedIP() else { return nil }
        return await api.getHouseHoldID(for: ip)
    }

    public func librarySearch(query: String) async -> [PlayableContent] {
        // MARK: Update use faster Sonos Devices if Available
        guard let ip = prioritizedIP() else { return [] }

        async let tracks = api.librarySearch(IP: ip, query: query, filter: .track)
        async let artist = api.librarySearch(IP: ip, query: query, filter: .artist)
        async let albums = api.librarySearch(IP: ip, query: query, filter: .album)
        // TODO: Prioritize by query
        let playableContent = await tracks + artist + albums
        return playableContent
    }

    public func libraryLookup(ID: String) async -> [PlayableContent] {
        guard let ip = prioritizedIP() else { return [] }
        let playableContent = await api.libraryLookup(IP: ip, id: ID)
        return playableContent
    }

    public func libraryAlbum(name: String) async -> [PlayableContent] {
        guard let ip = prioritizedIP() else { return [] }
        let playableContent = await api.libraryAlbumLookup(IP: ip, name: name)
        return playableContent
    }

    public func libraryArtist(name: String) async -> [PlayableContent] {
        guard let ip = prioritizedIP() else { return [] }
        let playableContent = await api.libraryArtistLookup(IP: ip, name: name)
        return playableContent
    }

    public func refreshLibrary() async {
        guard let ip = prioritizedIP() else { return  }
        await api.refreshLibrary(IP: ip)
    }

    // MARK: - Alarms
    public func listAlarms() async -> [Alarm] {
        guard let ip = prioritizedIP() else { return [] }
        return await api.listAlarms(IP: ip).sorted(by: { $0.startTime.compare($1.startTime) == .orderedAscending })
    }

    public func editAlarm(alarm: Alarm, content: PlayableContent?) async  {
        guard let ip = prioritizedIP() else { return }
        return await api.editAlarm(IP: ip, alarm: alarm, content: content)
    }

    public func createAlarm(alarm: Alarm, content: PlayableContent?) async  {
        guard let ip = prioritizedIP() else { return }
        return await api.createAlarm(IP: ip, alarm: alarm, content: content)
    }

    public func deleteAlarm(alarm: Alarm) async  {
        guard let ip = prioritizedIP() else { return }
        return await api.deleteAlarm(IP: ip, alarm: alarm)
    }

    public func parseAlarmClockInfo(uri: String, metadataXML: String?) -> PlayableContent? {
        XMLParserSonos().parseAlarmClockInfo(uri: uri, metadataXML: metadataXML)
    }

    func prioritizedIP() -> String? {
        let allRooms = groups.flatMap(\.rooms)
        guard let room = allRooms.first(where: { $0.ethernetEnabled }) else {
            let filteredRooms = allRooms.filter { room in
                guard let modelName = room.info?.modelName.lowercased() else { return false }
                let notTheseModels = ["roam", "move"]
                return notTheseModels.filter { modelName.contains($0) }.count == 0
            }

            if filteredRooms.isEmpty {
                return allRooms.first?.ip
            }

            return filteredRooms.first?.ip
        }
        return room.ip
    }
}



