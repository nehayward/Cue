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
    public var favorites: [PlayableContent] = []
    public var zones: OrderedDictionary<String, GroupRoom> = [:]

    public var rooms: [Room] = []
    public var selectedGroup: GroupRoom? = nil

    @ObservationIgnored private lazy var sonosSystemDiscoverService = SonosSystemDiscoverService()
    @ObservationIgnored private lazy var api = SonosAPI()
    @ObservationIgnored private lazy var mediaServerHandler = MediaServerHandler()

    @MainActor
    @ObservationIgnored private lazy var musicSearch = MusicSearchService()
    @ObservationIgnored private var isGroupingTask: Task<Void, Error> = Task { }

    public var systemState = SonosSystemState()
    public var isSearching: Bool { sonosSystemDiscoverService.isSearching }
    public var lastKnownIP: String { sonosSystemDiscoverService.sonosStorageIP.sonosIP }
    public var state: String { sonosSystemDiscoverService.lastKnownState }
    public var isCellular: Bool { sonosSystemDiscoverService.isCellular }

    @MainActor
    public func clearDevices() {
        // Cancel running tasks first to prevent concurrent access
        sonosPulse.cancel()
        watcher.cancel()
        monitorTask.cancel()

        zones.removeAll()
        groups.removeAll()
        rooms.removeAll()
        selectedGroup = nil
    }

    public var preferredHouseHold: String? { 
        get {
            sonosSystemDiscoverService.preferredHouseHold
        }
        set {
            sonosSystemDiscoverService.preferredHouseHold = newValue
        }
    }

    public var parserError: String?

    @ObservationIgnored public var monitorTask: Task<Void, Error> = Task { }
    @ObservationIgnored public var sonosPulse: Task<Void, Error> = Task { }
    @ObservationIgnored public var watcher: Task<Void, Error> = Task { }
    @ObservationIgnored public var isEditing: Bool = false
    @ObservationIgnored public var isGrouping: Bool = false
    @ObservationIgnored var streamingService: SonosStreamingService?
    @ObservationIgnored private var metadataTask: Task<Void, Never>?

    public var sortOption: SonosSortOption {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: "groupSortOption")
        }
    }

    public var isRunning: Bool { !sonosPulse.isCancelled }
    public var groupsChanged: (([GroupRoom]) -> ()) = { _ in }

    public init () {
        sonosPulse.cancel()
        let raw = UserDefaults.standard.integer(forKey: "groupSortOption")
        self.sortOption = SonosSortOption(rawValue: raw) ?? .nameAscending
        
        Task { @MainActor in
            self.streamingService = SonosStreamingService(eventHandler: self)
        }
    }

    public var system: System?

//    public var primaryHouseID: String? { sonosSystemDiscoverService.houseHoldIDs.first }
//    public var houseIDs: Set<String> { sonosSystemDiscoverService.houseHoldIDs }

    public var sorted: [GroupRoom] {
        get {
            switch sortOption {
            case .nameAscending:
                return groups.sorted(using: KeyPathComparator(\.coordinatorRoom.name))
            case .nameDescending:
                return groups.sorted(using: KeyPathComparator(\.coordinatorRoom.name, order: .reverse))
            case .playing:
                return groups.sorted { g1, g2 in
                    // First priority: TV Mode
                    if g1.tvSettings != nil && g2.tvSettings == nil { return true }
                    if g1.tvSettings == nil && g2.tvSettings != nil { return false }
                    
                    // Second priority: Playing status
                    if g1.coordinatorRoom.isPlaying == g2.coordinatorRoom.isPlaying {
                        return g1.coordinatorRoom.name < g2.coordinatorRoom.name
                    }
                    return g1.coordinatorRoom.isPlaying && !g2.coordinatorRoom.isPlaying
                }
            }
        }
        set {
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
    
    public func updateHousehold() async throws {
        let newGroup = try await getGroups(useCache: true)

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
                    try await load(useCache: useCache)
                    try? await Task.sleep(for: .milliseconds(selectedGroup != nil ? 500 : 800))

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
                } catch SonosServiceError.sonosSystemNotFound {
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
    public func load(useCache: Bool) async throws {
        let newGroup = try await getGroups(useCache: useCache)
        var refreshGroup: Bool = false

        // MARK: Update Battery Info And Other Room Information
        for updateGroup in newGroup {
            guard let index = groups.firstIndex(of: updateGroup) else { continue }
            groups[index].coordinatorRoom.ethernetEnabled = updateGroup.coordinatorRoom.ethernetEnabled
            groups[index].coordinatorRoom.micEnabled = updateGroup.coordinatorRoom.micEnabled
            groups[index].coordinatorRoom.battery = updateGroup.coordinatorRoom.battery

            // MARK: Fetch sleep timer for each group
            if updateGroup.coordinatorRoom.state == .active, groups[index].coordinatorRoom.sleepTimer == nil{
                groups[index].coordinatorRoom.sleepTimer = await api.getSleepTimer(IP: updateGroup.coordinatorRoom.ip)
            }

            if groups[index].coordinatorRoom.info == nil, updateGroup.coordinatorRoom.state == .active {
                // MARK: Update all rooms Info.
                groups[index].coordinatorRoom.info = await api.deviceInfo(IP: updateGroup.coordinatorRoom.ip)
            }

            for roomIndex in groups[index].rooms.indices {
                if groups[index].rooms[roomIndex].info == nil, updateGroup.coordinatorRoom.state == .active {
                    groups[index].rooms[roomIndex].info = await api.deviceInfo(IP: groups[index].rooms[roomIndex].ip)
                }

                guard !groups[index].rooms[roomIndex].settings.isSet else {
                    continue
                }
                groups[index].rooms[roomIndex].settings = await getSpeakerSettings(room: groups[index].rooms[roomIndex])
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
            guard !mediaServerHandler.deviceIP.isEmpty else { return }
            
            // MARK: I don't want to block
            Task {
                try await Task.sleep(for: .milliseconds(300))
                onServerListening()
            }
        }

        wakeSleepingRooms(rooms: rooms)

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
            async let availableActions = self.getCurrentTransportActions(ip: roomGroup.ip)
            async let mediaInfo = api.mediaInfo(ipAddress: roomGroup.ip)
            await updateGroupCheckTVMode(from: [roomGroup])

            guard !isEditing else { return }

            let isNowPlaying: Bool
            switch await playbackInfo {
            case .playing:
                isNowPlaying = true
            case .paused:
                isNowPlaying = false
            default:
                isNowPlaying = roomGroup.coordinatorRoom.isPlaying // keep current value
            }
            
            if roomGroup.coordinatorRoom.isPlaying != isNowPlaying {
                roomGroup.coordinatorRoom.isPlaying = isNowPlaying
            }

            if let updateGroupVolume = try? await groupVolume, !roomGroup.isEditingVolume, roomGroup.groupVolume != updateGroupVolume {
                roomGroup.groupVolume = updateGroupVolume
            }

            if let awaitedActions = await availableActions, await roomGroup.availableActions != availableActions {
                roomGroup.availableActions = awaitedActions
            }

            await updateGroupsRooms(from: [roomGroup])
            await updateGroupMuteState(for: [roomGroup])

            guard let awaitedTrack = await track else {
                return
            }
            
            if roomGroup.playbackService == .radio {
                if let mediaInfo = await mediaInfo, let title = mediaInfo.title, !title.isEmpty {
                    if roomGroup.coordinatorRoom.radioStation != title, !title.isEmpty {
                        roomGroup.coordinatorRoom.radioStation = title
                    }
                    
                    if roomGroup.coordinatorRoom.track.radioStationArtworkURL != mediaInfo.artwork {
                        roomGroup.coordinatorRoom.track.radioStationArtworkURL = mediaInfo.artwork
                    }
                }
            } else {
                roomGroup.coordinatorRoom.radioStation = nil
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
            if previousArtwork != nil, roomGroup.coordinatorRoom.track.downloadedArtworkURL != previousArtwork {
                roomGroup.coordinatorRoom.track.downloadedArtworkURL = previousArtwork
            }

            let currentTrack = roomGroup.coordinatorRoom.track
            if currentTrack.unique == awaitedTrack.unique {
                if !roomGroup.isEditingPlayback,
                   currentTrack.playbackPosition != awaitedTrack.playbackPosition {
                    currentTrack.playbackPosition = awaitedTrack.playbackPosition
                    return
                }
                
                if currentTrack.position != awaitedTrack.position {
                    currentTrack.position = awaitedTrack.position
                    return
                }
            }

            // Only get track information if the track ID has changed
            let shouldGetTrackInfo = roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique
            
            if shouldGetTrackInfo {
                roomGroup.coordinatorRoom.track = awaitedTrack
                guard let (trackMetadata, artworkURL) = await self.getTrackInformation(from: awaitedTrack) else {
                    if roomGroup.coordinatorRoom.track.id != awaitedTrack.trackID {
                        roomGroup.coordinatorRoom.track = awaitedTrack
                    } else if !roomGroup.isEditingPlayback {
                        roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                    }
                    return
                }

                awaitedTrack.downloadedArtworkURL = artworkURL
                if awaitedTrack.downloadedArtworkURL != artworkURL {
                    awaitedTrack.downloadedArtworkURL = artworkURL
                }
                awaitedTrack.metadata = trackMetadata

                if artworkURL != awaitedTrack.artworkURL {
                    roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                }

                if awaitedTrack.musicService == .tuneIn {
                    awaitedTrack.artist = trackMetadata?.artist ?? ""
                }
            } else {
                if !roomGroup.isEditingPlayback, isNowPlaying {
                    roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                }
            }

            if roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique {
                roomGroup.coordinatorRoom.track = awaitedTrack
                roomGroup.coordinatorRoom.track.downloadedArtworkURL = awaitedTrack.downloadedArtworkURL
            }

            Task {
                await ArtworkManager.shared.downScale(coordinatorRoom: roomGroup.nameWithCount, url: roomGroup.coordinatorRoom.track.artworkURL, trackID: roomGroup.coordinatorRoom.track.unique)
            }
            return
        }
        
        try await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self = self else { return }
            group.addTask { [weak self] in
                guard let self = self else { return }
                try await self.updateGroups(from: sorted)
            }
            
            group.addTask { [weak self] in
                guard let self = self else { return }
                await self.updateGroupCheckTVMode(from: sorted)
            }
            
            group.addTask { [weak self] in
                guard let self = self else { return }
                await self.updateGroupsRooms(from: sorted)
            }
            group.addTask { [weak self] in
                guard let self = self else { return }
                await self.updateGroupMuteState(for: sorted)
            }
            try await group.waitForAll()
        }
    }
    
    public func onServerListening() {
        // MARK: I don't want to block
        Task {
            await mediaServerHandler.start()
            guard let sonosIP = prioritizedIP() else { return }
            let preferredHouseHoldName = await api.getHouseHoldID(for: sonosIP)
            guard let deviceID = await api.getDeviceID(IP: sonosIP) else { return }
            KeychainTokenRefreshHandler.shared.deviceId = deviceID
            KeychainTokenRefreshHandler.shared.householdId = preferredHouseHoldName
            try? await api.subscribeToSonos(port: mediaServerHandler.port, deviceIP: mediaServerHandler.deviceIP, sonosIP: sonosIP)
        }
    }
    
    public func services() async -> [MediaServer] {
        guard let sonosIP = prioritizedIP() else { return [] }
        let preferredHouseHoldName = await api.getHouseHoldID(for: sonosIP)
        guard let servers = KeychainManager.shared.getMediaServers(householdId: preferredHouseHoldName) else { return [] }
        return servers
    }
    
    public func getPrimaryService(for serverType: SonosServiceType) async -> MediaServer? {
        guard let sonosIP = prioritizedIP() else { return nil }
        let preferredHouseHoldName = await api.getHouseHoldID(for: sonosIP)
        guard let servers = KeychainManager.shared.getMediaServers(householdId: preferredHouseHoldName),
              let primaryKey = KeychainTokenRefreshHandler.shared.getKey(for: serverType) else {
            return nil
        }
        let id = KeychainTokenRefreshHandler.shared.primaryServer?[primaryKey]
        return servers.first { $0.id == id }
    }
    
    public func setPrimaryServer(for server: MediaServer) async {
        guard let primaryKey = KeychainTokenRefreshHandler.shared.getKey(for: server.type) else { return }
        KeychainTokenRefreshHandler.shared.primaryServer?[primaryKey] = server.id
        KeychainTokenRefreshHandler.shared.setCredentials(for: server)
    }
    
    public func getCredentials() async -> (String, String)? {
        guard let sonosIP = try? await getGroupsFast().first?.ip else { return nil }
        let preferredHouseHoldName = await api.getHouseHoldID(for: sonosIP)
        guard let deviceID = await api.getDeviceID(IP: sonosIP) else { return nil }
        
        return (deviceID, preferredHouseHoldName)
    }

    @MainActor
    public func updateGroups(from groups: [GroupRoom]) async throws {
        await withDiscardingTaskGroup { group in
            for roomGroup in groups {
                group.addTask { [weak self] in
                    try? await self?.updateTrackInformation(for: [roomGroup])
                }
                
                group.addTask { [weak self] in
                    guard let self else { return }
                    // MARK: Sleeping or Off
                    if roomGroup.coordinatorRoom.state != .active { return }

                    async let playbackInfo = getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
                    async let groupVolume = getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
                    async let availableActions = getCurrentTransportActions(ip: roomGroup.ip)
                    async let queueTotal = getQueueTotal(group: roomGroup)

                    if let groupVolumeAwaited = try? await groupVolume, !roomGroup.isEditingVolume, roomGroup.groupVolume != groupVolumeAwaited {
                        roomGroup.groupVolume = groupVolumeAwaited
                    }
                    
                    if let queueTotalAwaited = try? await queueTotal {
                        roomGroup.coordinatorRoom.queueTotal = queueTotalAwaited
                    }

                    if let awaitedActions = await availableActions, await roomGroup.availableActions != availableActions {
                        roomGroup.availableActions = awaitedActions
                    }
                    
                    if roomGroup.coordinatorRoom.supportsFixedOutput {
                        let isOutputFixed = await api.getOutputFixed(IP: roomGroup.coordinatorRoom.ip)
                        if  roomGroup.coordinatorRoom.isOutputFixed != isOutputFixed {
                            roomGroup.coordinatorRoom.isOutputFixed = isOutputFixed
                        }
                    }
                    
                    let isNowPlaying: Bool
                    switch await playbackInfo {
                    case .playing:
                        isNowPlaying = true
                    case .paused:
                        isNowPlaying = false
                    default:
                        isNowPlaying = roomGroup.coordinatorRoom.isPlaying // keep current value
                    }

                    if roomGroup.coordinatorRoom.isPlaying != isNowPlaying {
                        roomGroup.coordinatorRoom.isPlaying = isNowPlaying
                    }
                }
            }
        }
    }
    
    @MainActor
    public func updateTrackInformation(for groups: [GroupRoom]) async throws {
        await withDiscardingTaskGroup { group in
            for roomGroup in groups {
                group.addTask { [weak self] in
                    guard let self else { return }
                    // MARK: Sleeping or Off
                    if roomGroup.coordinatorRoom.state != .active { return }
                    async let track = getTrack(ip: roomGroup.coordinatorRoom.ip)
                    async let mediaInfo = api.mediaInfo(ipAddress: roomGroup.coordinatorRoom.ip)

                    guard let awaitedTrack = await track else {
                        return
                    }
                    
                    if awaitedTrack == .tv {
                        roomGroup.playbackService = .tv
                     
                        if let settings = try? await getTVSettings(ip: roomGroup.ip), roomGroup.tvSettings != settings {
                            roomGroup.tvSettings = settings
                        }
                        return
                    }
                    
                    if roomGroup.playbackService == .radio {
                        if let mediaInfo = await mediaInfo, let title = mediaInfo.title, !title.isEmpty {
                            if roomGroup.coordinatorRoom.radioStation != title, !title.isEmpty {
                                roomGroup.coordinatorRoom.radioStation = title
                            }
                        }
                    } else if roomGroup.coordinatorRoom.radioStation != nil {
                        roomGroup.coordinatorRoom.radioStation = nil
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

                    let currentTrack = roomGroup.coordinatorRoom.track
                    if currentTrack.unique == awaitedTrack.unique {
                        if !roomGroup.isEditingPlayback, currentTrack.playbackPosition != awaitedTrack.playbackPosition {
                            currentTrack.playbackPosition = awaitedTrack.playbackPosition
                            return
                        }
                        
                        if currentTrack.position != awaitedTrack.position {
                            currentTrack.position = awaitedTrack.position
                            return
                        }
                        return
                    } else {
                        roomGroup.coordinatorRoom.track = awaitedTrack
                    }
                
                    guard let (trackMetadata, artworkURL) = await getTrackInformation(from: awaitedTrack) else {
                        if roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique {
                            roomGroup.coordinatorRoom.track = awaitedTrack
                        } else if !roomGroup.isEditingPlayback {
                            roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                        }
                        return
                    }

                    if awaitedTrack.downloadedArtworkURL != artworkURL {
                        awaitedTrack.downloadedArtworkURL = artworkURL
                    }
                    awaitedTrack.metadata = trackMetadata

                    if awaitedTrack.musicService == .tuneIn {
                        awaitedTrack.artist = trackMetadata?.artist ?? ""
                    }

                    if roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique {
                        roomGroup.coordinatorRoom.track = awaitedTrack
                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                    }
                    Task {
                        await ArtworkManager.shared.downScale(coordinatorRoom: roomGroup.nameWithCount, url: roomGroup.coordinatorRoom.track.artworkURL, trackID: roomGroup.coordinatorRoom.track.trackID)
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
    public func updateRoomVolumes(for groupRoom: GroupRoom) async {
        await withDiscardingTaskGroup { group in
            for room in groupRoom.rooms {
                group.addTask { [weak self] in
                    if room.state != .active { return }
                    if Task.isCancelled { return }
                    guard let self else { return }
                    if let volume = try? await getVolume(ip: room.ip), !room.isEditingVolume, room.volume != volume {
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
                group.addTask { [weak self] in
                    guard let self else { return }
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
                    if let playbackService = await playbackService(ip: roomGroup.ip), roomGroup.playbackService != playbackService {
                        Task { @MainActor in
                            roomGroup.playbackService = playbackService
                        }
                    }

                    // TODO: Move into playback
                    Task { @MainActor [weak self] in
                        if roomGroup.playbackService == .tv {
                            if let settings = try? await self?.getTVSettings(ip: roomGroup.ip), roomGroup.tvSettings != settings {
                                roomGroup.tvSettings = settings
                            }
                        } else if roomGroup.tvSettings != nil {
                            roomGroup.tvSettings = nil
                        }
                    }
                }
            }
        }
    }

    @MainActor
    public func updateGroupMuteState(for roomGroups: [GroupRoom]) async {
        await withDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                group.addTask { [weak self] in
                    guard let self else { return }
                    if roomGroup.coordinatorRoom.state == .active, let isMuted = await self.isMuted(for: roomGroup) {
                        Task { @MainActor in
                            if roomGroup.isMuted != isMuted {
                                roomGroup.isMuted = isMuted
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    public func wakeSleepingRooms(rooms: [Room]) {
        Task {
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
    }

    @MainActor
    func updateGroupsWatch(from roomGroups: [GroupRoom]) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                group.addTask { [weak self] in
                    guard let self else { return }
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

                    if let groupVolumeAwaited = try? await groupVolume, !roomGroup.isEditingVolume, roomGroup.groupVolume != groupVolumeAwaited {
                        roomGroup.groupVolume = groupVolumeAwaited
                    }

                    guard let awaitedTrack = await track else { return }

                    guard let artworkURL = await self.getArtwork(from: awaitedTrack, size: 200) else {
                        if roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique {
                            roomGroup.coordinatorRoom.track = awaitedTrack
                        } else {
                            roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                        }
                        return
                    }

                    if awaitedTrack.downloadedArtworkURL != roomGroup.coordinatorRoom.track.downloadedArtworkURL {
                        awaitedTrack.downloadedArtworkURL = roomGroup.coordinatorRoom.track.downloadedArtworkURL
                    }

                    if artworkURL != awaitedTrack.artworkURL {
                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                    }

                    if roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique {
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
    public func getGroupsFast() async throws -> [GroupRoom] {
        let ips = try await sonosSystemDiscoverService.getAllIPs()

        return try await withThrowingTaskGroup(of: [GroupRoom].self, returning: [GroupRoom].self) { taskGroup in
            for ip in ips {
                taskGroup.addTask { [weak self] in
                    guard let self else { return [] }
                    return try await api.getGroups(ipAddress: ip)
                }
            }

            // Return the first successful result
            if let firstGroups = try await taskGroup.next() {
                return firstGroups
            }

            // If no tasks succeeded, return an empty array
            return []
        }
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
    
    // Returns the new group
    public func speedGroup(rooms: [Room]) async -> GroupRoom? {
        // If there's only one room, ungroup it and return as a single group
        if rooms.count == 1, let room = rooms.first {
            await api.ungroup(IP: room.ip)
            return room.toGroup
        }
        
        // Get current groups, fallback to fetching them if necessary
        guard let currentGroups = !sorted.isEmpty ? sorted : try? await getGroupsFast() else {
            // Offline
            return nil
        }
        
        let coordinatorIDs = rooms.map(\.id)
        let filteredGroups = currentGroups.filter { group in
            group.rooms.map(\.id).contains(where: coordinatorIDs.contains)
        }
        
        // Update the playback state for filtered groups
        for idx in filteredGroups.indices {
            let playback = await getPlaybackInfo(ip: filteredGroups[idx].ip)
            filteredGroups[idx].coordinatorRoom.isPlaying = (playback == .playing)
        }
        
        // Check if exactly one group is playing
        let playingGroups = filteredGroups.filter { $0.coordinatorRoom.isPlaying }
        var coordinatorGroup: GroupRoom?
        
        if playingGroups.count >= 1 {
            // Use the single playing group as the coordinator group
            coordinatorGroup = playingGroups.first
        } else {
            // Normal logic: Find the first group matching coordinator IDs
            coordinatorGroup = filteredGroups.first(where: { coordinatorIDs.contains($0.coordinatorID) })
        }
        
        guard let coordinatorGroup else {
            // Offline
            return nil
        }
        
        // Group non-coordinator rooms to the coordinator group
        let nonCoordinatorRooms = rooms.filter { $0.id != coordinatorGroup.coordinatorID }
        for room in nonCoordinatorRooms {
            if !coordinatorGroup.rooms.contains(room) {
                await api.group(IP: room.ip, to: coordinatorGroup.coordinatorID)
            }
        }
        
        // Ungroup any extra rooms from the coordinator group
        for room in coordinatorGroup.rooms {
            if !rooms.contains(room) {
                await api.ungroup(IP: room.ip)
            }
        }
        
        return coordinatorGroup
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
        isGroupingTask = Task { [weak self] in
            guard let self else { return }
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
        await api.setGroupMute(IP: group.coordinatorRoom.ip, mute: mute)
    }

    @MainActor
    public func setRoomMute(room: Room, mute: Bool) async {
        room.isMuted = mute
        await api.setRoomMute(IP: room.ip, mute: mute)
    }
    
    public func setRoomMute(IP: String, mute: Bool) async {
        await api.setRoomMute(IP: IP, mute: mute)
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

    public func getTrackDetails(ip: String) async -> Track? {
        guard let track = await api.getCurrentTrack(ipAddress: ip, prioritizedAlbumArtIP: prioritizedIP()) else { return nil }
        guard let (trackMetadata, artworkURL) = await self.getTrackInformation(from: track) else {
            return track
        }
        track.downloadedArtworkURL = artworkURL
        track.metadata = trackMetadata
        if track.musicService == .tuneIn {
            track.artist = trackMetadata?.artist ?? ""
        }
        return track
    }
    
    @MainActor
    public func getTrackAudioInformation(ip: String, playerID: String, groupID: String) async {
        await streamingService?.addPlayer(.init(ipAddress: ip, playerId: playerID, groupId: groupID, events: [.metadata]))
    }
    
    public func stopListening(playerID: String) async {
        await streamingService?.removePlayer(playerID)
    }
    
    public func disconnectAll() async {
        await streamingService?.disconnectAll()
    }

    public func getArtwork(from track: Track, size: Int = 500) async -> URL? {
        switch track.musicService  {
        case .apple:
            guard let artworkString = await musicSearch.appleLookup(id: track.trackID)?.artworkURL(with: "\(size)"), let url = URL(string: artworkString) else {
                return nil
            }
            return url
        case .spotify:
//            var imageURL: URL?
//            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return nil }
//            
//            if let url = URL(string: spotifyTrack.albumArtURI) {
//                imageURL = url
//            }
//            return imageURL
            
            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return nil }
            guard let images = spotifyTrack.album.images else { return nil }
            if size == 100, let image = images.sorted(by: { $0.height ?? 0 < $1.height ?? 0 } ).first {
                guard let url = URL(string: image.url) else { return nil }
                return url
            }

            if size == 200, images.count > 2 {
                let image = images[1]
                guard let url = URL(string: image.url) else { return nil }
                return url
            }

            guard let artworkString = images.first?.url, let url = URL(string: artworkString) else { return nil }
            return url
        case .tidal:
            // TODO: Add back when production is enabled for Tidal
            return nil
//            guard let tidalTrack = await musicSearch.lookupTidalTrack(with: track.trackID) else { return nil }
//            return tidalTrack.artwork
        case .plex:
            guard let id = track.trackID.removingPercentEncoding?.components(separatedBy: ":").last, let plexSong = await musicSearch.lookupPlexSong(with: id) else {
                return nil
            }
            return plexSong.artwork
        case .soundcloud:
            guard let track = await musicSearch.lookupSoundCloudTrack(with: track.trackID) else { return nil }
            return track.artwork
        case .tuneIn:
            return nil
        case .airplay, .unknown, .library:
            return nil
        }
    }

    // TODO: Change size to enum
    public func getTrackInformation(from track: Track, size: Int = 500) async -> (Track.Metadata?, URL?)? {
        switch track.musicService {
        case .spotify:
//            var imageURL: URL?
//            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return (nil, nil) }
//            if let url = URL(string: spotifyTrack.albumArtURI) {
//                imageURL = url
//            }
//            
//            return (nil, imageURL)
            
            var imageURL: URL?
            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return (nil, nil) }

            if size == 100, let image = spotifyTrack.album.images?.sorted(by: { $0.height ?? 0 < $1.height ?? 0 } ).first {
                imageURL = URL(string: image.url)
            } else if size == 200, let images = spotifyTrack.album.images, images.count > 2  {
                let image = images[1]
                imageURL = URL(string: image.url)
            } else if let images = spotifyTrack.album.images, let artworkString = images.first?.url {
                imageURL = URL(string: artworkString)
            }

            return (Track.Metadata(ISRC: spotifyTrack.externalIds.isrc, openInURL: URL(string: spotifyTrack.externalUrls.spotify ?? ""), contentType: .track), imageURL)
        case .apple:
            var imageURL: URL? = nil
            if track.toPlayable.content.type == .libraryTrack {
                // TODO: Do 2 Searches, need to see if it's a catalog item.
                guard let appleTrack = await musicSearch.appleLibraryLookup(id: track.trackID) else {
                    return (nil, nil)
                }
                imageURL = appleTrack.data.first?.attributes.artwork?.urlWithSize(width: 500, height: 500)
                return (Track.Metadata(ISRC: nil, openInURL: appleTrack.data.first?.songURL, contentType: .libraryTrack), imageURL)
            }
            guard let appleTrack = await musicSearch.appleLookup(id: track.trackID) else { return (nil, nil) }
            imageURL = URL(string: appleTrack.artworkURL(with: "\(size)"))
            return (Track.Metadata(ISRC: nil, openInURL: URL(string: appleTrack.trackViewURL), contentType: .track), imageURL)
        case .tidal:
            guard let tidalTrack = await musicSearch.lookupTidalTrack(with: track.trackID) else { return (nil, nil) }
            return (Track.Metadata(ISRC: tidalTrack.metadata?.isrc, openInURL: tidalTrack.content.location, contentType: .track), tidalTrack.artwork)
        case .tuneIn:
            guard let stationID = track.metadata?.stationID, let tuneInTrack = await musicSearch.lookupTuneInStation(id: stationID) else { return (nil, nil) }

            // Store the station artwork URL as a fallback for when song artwork is unavailable
            let stationArtworkURL = tuneInTrack.imageURL
            track.radioStationArtworkURL = stationArtworkURL

            var imageURL = stationArtworkURL

            if let song = tuneInTrack.stationInfo?.song, let artist = tuneInTrack.stationInfo?.artist {
                if let spotifyArtwork = await musicSearch.searchApple(query: song + artist).first?.artwork {
                    imageURL = spotifyArtwork
                }
            }

            return (
                Track.Metadata(
                    ISRC: nil,
                    openInURL: tuneInTrack.stationInfo?.location,
                    contentType: .radio,
                    stationName: tuneInTrack.stationInfo?.name,
                    song: tuneInTrack.stationInfo?.song ?? tuneInTrack.stationInfo?.name,
                    album: tuneInTrack.stationInfo?.album,
                    artist: tuneInTrack.stationInfo?.artist
                ),
                imageURL
            )
        case .plex:
            guard let id = track.trackID.removingPercentEncoding?.components(separatedBy: ":").last,
                  let plexSong = await musicSearch.lookupPlexSong(with: id) else {
                return (nil, nil)
            }
            return (
                Track.Metadata(
                    ISRC: nil,
                    openInURL: nil,
                    contentType: .track,
                    song: nil,
                    album: plexSong.metadata?.album,
                    artist: plexSong.metadata?.artist
                ),
                plexSong.artwork
            )
        case .soundcloud:
            guard let track = await musicSearch.lookupSoundCloudTrack(with: track.trackID) else { return nil }
            return (
                Track.Metadata(
                    ISRC: track.metadata?.isrc,
                    openInURL: track.content.location,
                    contentType: .track,
                    song: nil
                ),
                track.artwork
            )
        case .unknown:
            if track.metadata?.contentType != .track { return (nil, nil) }
            guard let artworkURL = await musicSearch.searchSpotifySong(song: track.name, artist: track.artist)?.tracks?.items.first else {
                return (nil, nil)
            }

            return (Track.Metadata(ISRC: nil, openInURL: nil, contentType: .track), artworkURL.album.images?.biggestImageURL)
        case .airplay, .library:
            return (nil, nil)
        }
    }

    public func getArtwork(from content: PlayableContent, size: Int = 500) async -> URL? {
        switch (content.content.type, content.content.service) {
        case (.album, .spotify):
            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id), let images = album.images else { return nil }

            if size == 50 {
                return images.thumbnail
            } else if size > 100, images.count > 2 {
                let image = images[1]
                return URL(string: image.url)
            } else if size == 200 {
                return images.thumbnail
            }
            return images.biggestImageURL
        case (.track, .spotify):
//            var imageURL: URL?
//            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
//            
//            if let url = URL(string: spotifyTrack.albumArtURI) {
//                imageURL = url
//            }
//            return imageURL
            var imageURL: URL?
            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: content.id), let images = spotifyTrack.album.images else { return nil }

            if size == 50 {
                return images.thumbnail
            } else if size > 100, images.count > 2 {
                let image = images[1]
                imageURL = URL(string: image.url)
            } else if let artworkString = images.first?.url {
                imageURL = URL(string: artworkString)
            }

            return imageURL
        case (.playlist, .spotify):
            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
            return playlist.images?.biggestImageURL
        case (.track, .apple):
            guard let track = await musicSearch.appleLookup(id: content.id) else { return nil }
            return URL(string: track.artworkURL)
        case (.libraryTrack, .apple):
            guard let track = await musicSearch.appleLibraryLookup(id: content.id) else {
                return nil
            }
            return track.data.first?.attributes.artwork?.urlWithSize(width: size, height: size)
        case (.album, .apple):
            guard let album: Album = try? await musicSearch.lookup(id: content.id) else { return nil }
            return album.artwork?.url(width: size, height: size)
        case (.playlist, .apple):
            guard let playlist: Playlist = try? await musicSearch.lookup(id: content.id) else { return nil }
            return playlist.artwork?.url(width: size, height: size)
        case (.libraryArtist, .apple):
            return await musicSearch.appleLibraryArtistArtwork(name: content.title)
        case (.artist, .library):
            return await musicSearch.appleLibraryArtistArtwork(name: content.title)
        case (.track, .plex):
            guard let id = content.id.removingPercentEncoding?.components(separatedBy: ":").last else { return nil }
            
            let track = await musicSearch.lookupPlexSong(with: id)
            if size == 50 {
                return track?.thumbnail
            } else {
                return track?.artwork
            }
        case (.track, .soundcloud):
            guard let track = await musicSearch.lookupSoundCloudTrack(with: content.id) else { return nil }
            return track.artwork
        default:
//            print(content)
            return nil
        }
    }

    public func getContent(from url: URL) async -> PlayableContent? {
        guard let content = api.parse(url: url) else { return nil }
        switch (content.type, content.service) {
        case (.album, .spotify):
            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id) else { return nil }
            return PlayableContent(title: album.name, subtitle: album.artists?.first?.name ?? "", thumbnail: album.images?.thumbnail, artwork: album.images?.biggestImageURL, content: content)
        case (.track, .spotify):
            guard let track = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
            return PlayableContent(title: track.name, subtitle: track.artists.first?.name ?? "", thumbnail: track.album.images?.thumbnail, artwork: track.album.images?.biggestImageURL, content: content)
        case (.playlist, .spotify):
            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
            return PlayableContent(title: playlist.name, subtitle: playlist.owner.displayName, thumbnail: playlist.images?.thumbnail, artwork: playlist.images?.biggestImageURL, content: content)
        case (.track, .apple):
            guard let song: Song = try? await musicSearch.lookup(id: content.id) else { return nil }
            return PlayableContent(title: song.title, subtitle: song.artistName, thumbnail: song.artwork?.url(width: 100, height: 100), artwork: song.artwork?.url(width: 500, height: 500), content: content)
        case (.album, .apple):
            guard let album: Album = try? await musicSearch.lookup(id: content.id) else { return nil }
            return PlayableContent(title: album.title, subtitle: album.artistName, thumbnail: album.artwork?.url(width: 100, height: 100), artwork: album.artwork?.url(width: 500, height: 500), content: content)
        case (.playlist, .apple):
            guard let playlist: Playlist = try? await musicSearch.lookup(id: content.id) else { return nil }
            return PlayableContent(title:   playlist.name, subtitle: playlist.curatorName ?? "", thumbnail: playlist.artwork?.url(width: 100, height: 100), artwork: playlist.artwork?.url(width: 500, height: 500), content: content)
        case (.track, .tidal):
            guard let playableContent = await musicSearch.lookupTidalTrack(with: content.id) else { return nil }
            return playableContent
        case (.album, .tidal):
            guard let playableContent = await musicSearch.lookupTidalAlbum(with: content.id) else { return nil }
            return playableContent
        case (_, .tuneIn):
            guard let tuneInStation = await musicSearch.lookupTuneInStation(id: content.id) else { return nil }
            return tuneInStation.toPlayable
//        case (.playlist, .tidal):
//            guard let playlist: Playlist = try? await musicSearch.(with: content.id) else { return nil }
//            return PlayableContent(title: playlist.name, subtitle: playlist.curatorName ?? "", artwork: playlist.artwork?.url(width: 500, height: 500), content: content)
        case (.track, .plex):
            guard let id = content.id.removingPercentEncoding?.components(separatedBy: ":").last,
                  let track = await musicSearch.lookupPlexSong(with: id) else { return nil }
            return track
        case (.album, .plex):
            guard let id = content.id.removingPercentEncoding?.components(separatedBy: ":").last,
                  let album = await musicSearch.lookupPlexAlbum(id: id) else { return nil }
            return album
        case (.playlist, .plex):
            return nil
//            guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
////                  let playlist = await musicSearch.lookuple(id: id) else { return nil }
//            return album
        case (.track, .soundcloud):
            guard let track = await musicSearch.lookupSoundCloudTrack(with: content.id) else { return nil }
            return track
        default:
            return nil
        }
    }
    
    public func contentLookup(id: String, type: ContentType, service: MusicService) async -> PlayableContent? {
        let content = MediaContent(service: service, id: id, type: type, location: nil)
        
        switch (type, service) {
        case (.album, .spotify):
            guard let album = await musicSearch.spotifyAlbumLookup(id: id) else { return nil }
            return PlayableContent(title: album.name, subtitle: album.artists?.first?.name ?? "", thumbnail: album.images?.thumbnail, artwork: album.images?.biggestImageURL, content: content)
        case (.track, .spotify):
            guard let track = await musicSearch.spotifyTrackLookup(id: id) else { return nil }
            return PlayableContent(title: track.name, subtitle: track.artists.first?.name ?? "", thumbnail: track.album.images?.thumbnail, artwork: track.album.images?.biggestImageURL, content: content)
        case (.playlist, .spotify):
            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: id) else { return nil }
            return PlayableContent(title: playlist.name, subtitle: playlist.owner.displayName, thumbnail: playlist.images?.thumbnail, artwork: playlist.images?.biggestImageURL, content: content)
        case (.track, .apple):
            guard let song: Song = try? await musicSearch.lookup(id: id) else { return nil }
            return PlayableContent(title: song.title, subtitle: song.artistName, thumbnail: song.artwork?.url(width: 100, height: 100), artwork: song.artwork?.url(width: 500, height: 500), content: content)
        case (.album, .apple):
            guard let album: Album = try? await musicSearch.lookup(id: id) else { return nil }
            return PlayableContent(title: album.title, subtitle: album.artistName, thumbnail: album.artwork?.url(width: 100, height: 100), artwork: album.artwork?.url(width: 500, height: 500), content: content)
        case (.playlist, .apple):
            guard let playlist: Playlist = try? await musicSearch.lookup(id: id) else { return nil }
            return PlayableContent(title: playlist.name, subtitle: playlist.curatorName ?? "", thumbnail: playlist.artwork?.url(width: 100, height: 100), artwork: playlist.artwork?.url(width: 500, height: 500), content: content)
        case (.libraryTrack, .apple):
//            guard let song: Song = try? await musicSearch.lookup(id: id) else { return nil }
//            return PlayableContent(title: song.title, subtitle: song.artistName, thumbnail: song.artwork?.url(width: 100, height: 100), artwork: song.artwork?.url(width: 500, height: 500), content: content)
            return nil
        case (.libraryAlbum, .apple):
            let libraryAlbum = await musicSearch.appleLibraryAlbum(id: id)
            return libraryAlbum?.data.first?.toPlayable
        case (.libraryPlaylist, .apple):
            let libraryAlbum = await musicSearch.appleLibraryPlaylist(id: id)
            return libraryAlbum?.data.first?.toPlayable
        case (.track, .tidal):
            guard let playableContent = await musicSearch.lookupTidalTrack(with: id) else { return nil }
            return playableContent
        case (.album, .tidal):
            guard let playableContent = await musicSearch.lookupTidalAlbum(with: id) else { return nil }
            return playableContent
        case (_, .tuneIn):
            guard let tuneInStation = await musicSearch.lookupTuneInStation(id: id) else { return nil }
            return tuneInStation.toPlayable
        case (.track, .plex):
            guard let decodedId = id.removingPercentEncoding?.components(separatedBy: ":").last,
                  let track = await musicSearch.lookupPlexSong(with: decodedId) else { return nil }
            return track
        case (.album, .plex):
            guard let decodedId = id.removingPercentEncoding?.components(separatedBy: ":").suffix(2).first,
                  let album = await musicSearch.lookupPlexAlbum(id: decodedId) else { return nil }
            return album
        case (.playlist, .plex):
            guard let decodedId = id.removingPercentEncoding?.components(separatedBy: ":").suffix(2).first,
                  let playlist = await musicSearch.lookupPlexPlaylist(id: decodedId) else { return nil }
            return playlist
        case (.track, .soundcloud):
            guard let track = await musicSearch.lookupSoundCloudTrack(with: id) else { return nil }
            return track
        case (.playlist, .library):
            let playlist = await libraryPlaylistLookup(ID: id)
            return playlist
        case (_, .library):
            let track = await libraryLookup(ID: id)
            return track.first
        default:
            return nil
        }
    }

    public func pause(ip: String) async {
        let groupIndex = groups.firstIndex { group in
            group.coordinatorRoom.ip == ip
        }

        if let groupIndex {
            for (index, _) in groups[groupIndex].rooms.enumerated() {
                Task { @MainActor in
                    groups[groupIndex].rooms[index].isPlaying = false
                    groups[groupIndex].coordinatorRoom.isPlaying = false
                }
            }
        }

        isEditing = true
        await api.pause(ipAddress: ip)
        try? await Task.sleep(for: .milliseconds(400))
        isEditing = false
    }

    public func play(ip: String) async {
        let groupIndex = groups.firstIndex { room in
            room.coordinatorRoom.ip == ip
        }

        if let groupIndex {
            Task { @MainActor in
                for (index, _) in groups[groupIndex].rooms.enumerated() {
                    groups[groupIndex].rooms[index].isPlaying = true
                    groups[groupIndex].coordinatorRoom.isPlaying = true
                }
            }
        }
        isEditing = true
        await api.play(ipAddress: ip)
        try? await Task.sleep(for: .milliseconds(400))
        isEditing = false
    }

    public func next(ip: String) async {
        await api.next(ipAddress: ip)
    }

    /// If playback is more than 3 seconds into the track, restarts the current track.
    /// Otherwise, goes to the previous track.
    public func previous(ip: String) async {
        let track = await api.getCurrentTrack(ipAddress: ip)
        let playbackPosition = track?.playbackPosition ?? 0
        if playbackPosition >= 3000 {
            await api.seek(to: TimeInterval(0), IP: ip)
        } else {
            await api.previous(ipAddress: ip)
        }
    }

    public func isMuted(for group: GroupRoom) async -> Bool? {
        await api.getGroupMute(IP: group.coordinatorRoom.ip)
    }
    
    public func isRoomMuted(for ip: String) async -> Bool? {
        await api.getRoomMute(IP: ip)
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
        await api.mediaInfo(ipAddress: ip)?.playbackService
    }

    // MARK: TV
    public func getTVSettings(ip: String) async throws -> TVSettings {
        async let audioInputFormat = api.getAudioInputFormat(IP: ip)
        async let dialogLevel = api.getDialogLevel(IP: ip)
        async let nightMode = api.getNightMode(IP: ip)
        
        return try await TVSettings(
            nightMode: nightMode,
            dialogLevel: dialogLevel,
            audioInputFormat: audioInputFormat
        )
    }

    public func setDialogLevel(_ IP: String, enabled: Bool) async throws {
        try await api.setDialogLevel(IP: IP, enabled: enabled)
    }

    public func setNightMode(_ IP: String, enabled: Bool) async throws {
        try await api.setNightMode(IP: IP, enabled: enabled)
    }

    public func tvInput(group: GroupRoom) async {
        guard let firstSoundBar = group.rooms.first(where: \.isSoundbar) else { return }
        await api.tvInput(IP: firstSoundBar.ip, ID: firstSoundBar.id)
    }
    
    public func switchToLineIn(group: GroupRoom) async {
        await api.switchToLineIn(IP: group.ip, ID: group.coordinatorRoom.id)
    }
    
    public func switchToQueueInput(group: GroupRoom) async {
        await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
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
        let playlistAction = { [weak self] (group: GroupRoom) in
            guard let self else { return }
            guard let playableContent = scene.playableContent else { return }
            if let playMode = scene.playMode {
                await setPlayMode(group.ip, mode: playMode)
            }
            try await queue(playable: playableContent, group: group, position: scene.position ?? .now)
            await play(ip: group.ip)
        }
        
        // Update household if no groups are available
        if groups.isEmpty {
            try await updateHousehold()
        }
        
        // Create a lookup dictionary for better performance
        let roomLookup = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        
        // Map scene rooms to discovered rooms with better error handling
        let discoveredSceneRooms = try scene.rooms.map { sceneRoom in
            guard let existingRoom = roomLookup[sceneRoom.id] else {
                throw SonosAPIError.deviceNotFound
            }
            return SceneRoom(
                id: existingRoom.id, 
                ip: existingRoom.ip, 
                name: existingRoom.name, 
                volume: sceneRoom.volume
            )
        }
        
        // Create rooms for grouping
        let rooms = discoveredSceneRooms.map { Room(id: $0.id, ip: $0.ip, name: $0.name) }
        
        // Create the group
        if scene.volumeOnly {
            // Set volume and unmute all rooms concurrently for better performance
            await withTaskGroup(of: Void.self) { group in
                for room in discoveredSceneRooms {
                    group.addTask {
                        await self.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                        await self.setRoomMute(IP: room.ip, mute: false)
                    }
                }
            }
            return
        }
        
        guard let newGroup = await speedGroup(rooms: rooms) else {
            throw SonosAPIError.deviceNotFound
        }
        
        // Set volume and unmute all rooms concurrently for better performance
        await withTaskGroup(of: Void.self) { group in
            for room in discoveredSceneRooms {
                group.addTask {
                    await self.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                    await self.setRoomMute(IP: room.ip, mute: false)
                }
            }
        }
        
        // Take snapshot and execute playlist action concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.snapShotGroup(ip: newGroup.ip)
            }
            group.addTask {
                try? await playlistAction(newGroup)
            }
        }

        if let duration = scene.sleepTimer {
            await sleepTimer(group: newGroup, duration: duration)
        }
    }

    public func seek(trackNumber: Int, on group: GroupRoom) async {
        let queueActive = group.playbackService == .queue
        if !queueActive {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }
        await api.seek(trackNumber: trackNumber, IP: group.coordinatorRoom.ip)
        try? await Task.sleep(for: .milliseconds(80))
        try? await updateGroups(from: [group])
    }

    public func getFavoriteList() async {
        guard let ip = prioritizedIP() else { return }
        self.favorites = await api.getFavorites(for: ip)
    }

    public func deleteFavorite(on group: GroupRoom?, favoriteID: String) async {
        guard let foundGroup = groups.first else { return }
        await api.deleteFavorite(IP: group?.ip ?? foundGroup.ip, itemID: favoriteID)
    }

    public func seek(to time: TimeInterval, on group: GroupRoom) async {
        await api.seek(to: time, IP: group.coordinatorRoom.ip)
    }
    
    public func queueSpotifyArtistTopTracks(id: String, group: GroupRoom) async {
        if group.playbackService != .queue {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }
        await api.queueSpotifyArtistTopTracks(ID: id, IP: group.ip)
    }

    private func queuePlayable(playable: PlayableContent, group: GroupRoom, position: QueuePosition = .now, index: Int? = nil) async throws {
        if let index, index > 0, position != .next, !playable.content.type.isTrack, group.playMode != .normal {
            await setPlayMode(group.ip, mode: .normal)
            group.playMode = .normal
        }

        if [.favorite, .radio, .liveRadio, .artistRadio, .songRadio].contains(playable.content.type) {
            try await api.setAVTransportContent(playableContent: playable, IP: group.ip)
            return
        }
        
        if playable.content.type.isRadio {
            try await startRadio(content: playable, group: group)
            return
        }
        
        if group.playbackService == .unknown {
            group.playbackService = await playbackService(ip: group.ip) ?? .unknown
        }
        
        let queueActive = group.playbackService == .queue

        if position == .replace {
            await api.removeAllTrackFromQueue(IP: group.ip)
        }

        let shuffling = group.playMode.isShuffleEnabled

        if !queueActive {
            try await api.queuePlayable(playableContent: playable, IP: group.ip, position: .front, shuffling: shuffling)
            if let index, index > 0 {
                let current = await api.getCurrentQueueIndex(ipAddress: group.ip)
                await seek(trackNumber: current + index, on: group)
                return
            }
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
            return
        }

        let count = await api.getQueueCount(IP: group.ip)
        try await api.queuePlayable(playableContent: playable, IP: group.ip, position: position, shuffling: shuffling)
        
        if let index, index > 0, position == .now || position == .replace {
            let current = await api.getCurrentQueueIndex(ipAddress: group.ip)
            await seek(trackNumber: current + index, on: group)
            return
        }

        if position == .now, queueActive, playable.content.type != .playlist, let count, count > 0 {
            await next(ip: group.ip)
        }
    }
        
    public func getQueueTotal(group: GroupRoom) async throws -> Int? {
        let count = await api.getQueueCount(IP: group.ip)
        return count
    }
    
    public func replaceQueue(playable: PlayableContent, group: GroupRoom, index: Int = 0) async throws {
        if index > 0, !playable.content.type.isTrack, group.playMode != .normal {
            await setPlayMode(group.ip, mode: .normal)
        }
        try await api.replaceQueue(playableContent: playable, IP: group.ip, index: index)
        await api.play(ipAddress: group.ip)
        try? await Task.sleep(for: .milliseconds(120))
        try? await updateGroups(from: [group])
    }

    public func queue(playable: PlayableContent, group: GroupRoom, position: QueuePosition = .now, index: Int? = nil) async throws {
        try await queuePlayable(playable: playable, group: group, position: position, index: index)
        try? await Task.sleep(for: .milliseconds(120))
        try? await updateGroups(from: [group])
    }
    
    /// Plays the first item immediately on a Sonos group, then queues the remaining
    /// items to play next in order.
    ///
    /// Note: Sonos treats `.next` as LIFO, so remaining items are enqueued in reverse
    /// to preserve the caller’s order.
    public func playNext(
        _ contents: [PlayableContent],
        on group: GroupRoom
    ) async throws {
        guard !contents.isEmpty else {
            assertionFailure("playNext called with empty contents")
            return
        }

        // Ensure queue-based playback
        if group.playbackService != .queue {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }

        let first = contents[0]
        let remainder = contents.dropFirst()
        let shuffling = group.playMode.isShuffleEnabled

        // Play first item immediately
        try await api.queuePlayable(
            playableContent: first,
            IP: group.ip,
            position: .now,
            shuffling: shuffling
        )

        // Activate transport
        await next(ip: group.ip)
        await play(ip: group.ip)

        try? await Task.sleep(for: .milliseconds(150))
        try? await updateGroups(from: [group])

        // Queue remaining items (reverse to preserve order)
        for content in remainder.reversed() {
            try await api.queuePlayable(
                playableContent: content,
                IP: group.ip,
                position: .next,
                shuffling: shuffling
            )
        }

        try? await Task.sleep(for: .milliseconds(150))
        try? await updateGroups(from: [group])
    }
    
    /// Queues items on a Sonos group at the requested position.
    ///
    /// Note: Sonos treats `.next` as LIFO, so `.next` insertions are reversed
    /// to preserve the caller’s order.
    public func queue(
        contents: [PlayableContent],
        group: GroupRoom,
        position: QueuePosition = .end
    ) async throws {
        guard !contents.isEmpty else {
            assertionFailure("queue called with empty contents")
            return
        }

        // Ensure queue-based playback
        if group.playbackService != .queue {
            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
        }

        // Replace clears queue first
        if position == .replace {
            await api.removeAllTrackFromQueue(IP: group.ip)
        }

        let shuffling = group.playMode.isShuffleEnabled
        let sequence = position == .next ? contents.reversed() : contents
        let enqueuePosition: QueuePosition = position == .replace ? .end : position

        for (index, content) in sequence.enumerated() {
            try await api.queuePlayable(playableContent: content, IP: group.ip, position: enqueuePosition, shuffling: shuffling)

            // Start playback as soon as the first item is queued
            if position == .now && index == 0 {
                await next(ip: group.ip)
                await play(ip: group.ip)
            }
        }

        try? await Task.sleep(for: .milliseconds(150))
        try? await updateGroups(from: [group])
    }

    public func getQueue(ip: String, with startingIndex: Int? = nil, total: Int = 50) async -> [PlayableContent] {
        if let startingIndex = startingIndex {
            return await api.getQueue(IP: ip, startingIndex: startingIndex, total: total, priorityIP: prioritizedIP())
        } else {
            return await api.getQueue(IP: ip, prioritizedAlbumArtIP: prioritizedIP())
        }
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

    public func startRadio(content: PlayableContent, group: GroupRoom) async throws {
        try await api.startRadio(playableContent: content, IP: group.ip)
        await api.play(ipAddress: group.ip)
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
        guard let ip = prioritizedIP() else { return nil }
        return await api.getHouseHoldID(for: ip)
    }

    public func getHouseID(for ip: String) async -> String? {
        return await api.getHouseHoldID(for: ip)
    }

    public func getAllHouseholdsIPs() async -> Set<String> {
        guard let ips = try? await sonosSystemDiscoverService.getAllIPs() else { return [] }

        var householdMap = [String: String]()
        var savedIPs = Set<String>()
        
        await withTaskGroup(of: (String, String).self) { taskGroup in
            for ip in ips {
                taskGroup.addTask { [weak self] in
                    guard let self else { return ("", "") }
                    let householdID = await self.api.getHouseHoldID(for: ip)
                    return (householdID, ip)
                }
            }

            for await (householdID, ip) in taskGroup {
                if householdMap[householdID] == nil {
                    householdMap[householdID] = ip
                    savedIPs.insert(ip)
                }
            }
        }

        print(householdMap)
        return savedIPs
    }

    public func librarySearch(query: String) async -> [PlayableContent] {
        // MARK: Update use faster Sonos Devices if Available
        guard let ip = prioritizedIP() else { return [] }

        async let tracks = api.librarySearch(IP: ip, query: query, filter: .track)
        async let artist = api.librarySearch(IP: ip, query: query, filter: .artist)
        async let albums = api.librarySearch(IP: ip, query: query, filter: .album)
        async let playlist = api.librarySearch(IP: ip, query: query, filter: .playlist)
        async let sonosPlaylist = api.sonosPlaylists(IP: ip)
        // TODO: Prioritize by query
        let playableContent = await tracks + artist + albums + playlist + sonosPlaylist.filter{$0.title.localizedCaseInsensitiveContains(query)}
        return playableContent
    }
    
    public func libraryPlaylistLookup(ID: String) async -> PlayableContent? {
        var id = ID
        guard let ip = prioritizedIP() else { return nil }
        if !id.contains("SQ") {
            id = "SQ:\(id)"
        }
        
        let playableContent = await api.libraryPlaylistLookup(IP: ip, id: id)
        return playableContent.first
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

    // MARK: - Sonos Playlists/Queue
    public func sonosPlaylists() async -> [PlayableContent] {
        // MARK: Update use faster Sonos Devices if Available
        guard let ip = prioritizedIP() else { return [] }
        return await api.sonosPlaylists(IP: ip)
    }

    public func sonosPlaylistsTracks(for id: String, offset: Int = 0, limit: Int = 100) async -> [PlayableContent] {
        guard let ip = prioritizedIP() else { return [] }
        return await api.sonosPlaylistsTracks(IP: ip, id: id, offset: offset, limit: limit)
    }

    public func createPlaylist(title: String) async {
        // MARK: Update use faster Sonos Devices if Available
        guard let ip = prioritizedIP() else { return }
        return await api.createPlaylist(IP: ip, title: title)
    }

    public func delete(playlistID: String) async {
        // MARK: Update use faster Sonos Devices if Available
        guard let ip = prioritizedIP() else { return }
        return await api.removePlaylist(IP: ip, itemID: playlistID)
    }

    public func addToPlaylist(playlistID: String, playableContent: PlayableContent) async {
        // MARK: Update use faster Sonos Devices if Available
        guard let ip = prioritizedIP() else { return }
        return await api.addToPlaylist(IP: ip, playlistID: playlistID, content: playableContent)
    }

    public func reorderPlaylist(playlistID: String, from: Int, to: Int) async throws {
        guard let ip = prioritizedIP() else { return }
        await api.reorderSavedQueue(IP: ip, from: from, to: to, savedQueueID: playlistID)
    }

    public func removeTrackFromPlaylist(playlistID: String, index: Int) async throws {
        guard let ip = prioritizedIP() else { return }
        await api.removeTrackFromSavedQueue(IP: ip, trackID: String(index), savedQueueID: playlistID)
    }

    public func saveQueue(ip: String, title: String) async throws {
        await api.saveQueue(IP: ip, title: title)
    }

    public func renamePlaylist(existingPlaylist: PlayableContent, newName: String) async throws {
        guard let ip = prioritizedIP() else { return }
        await api.renamePlaylist(IP: ip, playlistID: existingPlaylist.id, oldName: existingPlaylist.title, newName: newName)
    }

    // MARK: - Speaker Settings
    public func info(room: Room) async -> DeviceInfo? {
        await api.deviceInfo(IP: room.ip)
    }
    
    public func getSpeakerSettings(room: Room) async -> SpeakerSettings {
        async let bass = api.getBass(ipAddress: room.ip) ?? 0
        async let treble = api.getTreble(ipAddress: room.ip) ?? 0
        async let loudness = api.getLoudness(ipAddress: room.ip) ?? false
        async let isTrueplayEnabled = api.getTrueplayEnabled(ipAddress: room.ip) ?? false

        return SpeakerSettings(
            isSet: true,
            bass: await Double(bass),
            treble: await Double(treble),
            loudness: await loudness,
            truePlay: await isTrueplayEnabled
        )
    }

    public func setBass(room: Room) async {
        await api.setBass(ipAddress: room.ip, bass: Int(room.settings.bass))
    }

    public func setTreble(room: Room) async {
        await api.setTreble(ipAddress: room.ip, treble: Int(room.settings.treble))
    }

    public func setLoudness(room: Room) async {
        await api.setLoudness(ipAddress: room.ip, enabled: room.settings.loudness)
    }

    public func getEQ(room: Room, eq: EQType) async -> Double {
        await api.getEQValue(IP: room.ip, eq: eq) ?? 0.0
    }

    public func setEQ(room: Room, eq: EQType, value: Int) async {
        await api.setEQValue(IP: room.ip, eq: eq, value: value)
    }

    public func resetEQ(room: Room) async {
        await api.resetEQ(ipAddress: room.ip)
    }

    // MARK: Theater Settings
    public func getTheaterSettings(room: Room) async -> TheaterSettings {
        async let audioInputFormat = api.getAudioInputFormat(IP: room.ip)
        async let dialogLevel = api.getDialogLevel(IP: room.ip)
        async let nightMode = api.getNightMode(IP: room.ip)
        async let subGain = api.getEQValue(IP: room.ip, eq: .subGain)
        async let isSubEnabled = api.getEQValue(IP: room.ip, eq: .subEnable)
        async let surroundMode = api.getEQValue(IP: room.ip, eq: .surroundMode)
        async let musicSurroundLevel = api.getEQValue(IP: room.ip, eq: .musicSurroundLevel)
        async let surroundLevel = api.getEQValue(IP: room.ip, eq: .surroundLevel)
        async let surroundEnabled = api.getEQValue(IP: room.ip, eq: .surroundEnable)
        async let heightLevel = api.getEQValue(IP: room.ip, eq: .heightChannelLevel)

        return TheaterSettings(
            isSet: true,
            nightMode: (try? await nightMode) ?? false,
            dialogLevel: (try? await dialogLevel) ?? false,
            audioInputFormat: (try? await audioInputFormat) ?? .unknown,
            surroundLevel: await surroundLevel ?? 0.0,
            musicSurroundLevel: await musicSurroundLevel ?? 0.0,
            isSurroundEnable: await (surroundEnabled ?? 0) == 1 ? true : false,
            surroundMode:  await surroundMode ?? 0.0,
            heightChannel: await heightLevel ?? 0.0,
            subGain: await subGain ?? 0.0,
            isSubEnabled: await (isSubEnabled ?? 0) == 1 ? true : false
        )
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
        let sortedRooms = allRooms.sorted { lhs, rhs in
            // Ethernet-enabled rooms should come last
            let lhsEthernet = lhs.ethernetEnabled ? 1 : 0
            let rhsEthernet = rhs.ethernetEnabled ? 1 : 0
            return lhsEthernet < rhsEthernet
        }
        
        // Filter out portable models like Roam and Move
        let filteredRooms = sortedRooms.filter { room in
            guard let modelName = room.info?.modelDisplayName.lowercased() else { return false }
            let excludedModels = ["roam", "move", "play"]
            return !excludedModels.contains { modelName.contains($0) }
        }
        
        // Return the best matching room IP
        if let bestRoom = filteredRooms.sorted(by: {
            ($0.info?.model ?? "").localizedStandardCompare($1.info?.model ?? "") == .orderedDescending
        }).first {
            return bestRoom.ip
        }
        
        // Fallback
        return allRooms.first?.ip
    }
    
    func priorityDevice() -> Room? {
        let excludedModels = ["roam", "move", "play"]
        
        let allRooms = groups.flatMap(\.rooms)
        
        // Filter out portable models
        let nonPortableRooms = allRooms.filter { room in
            guard let modelName = room.info?.modelDisplayName.lowercased() else { return true }
            return !excludedModels.contains(where: { modelName.contains($0) })
        }
        
        // Prefer Ethernet-enabled devices first
        let sortedRooms = nonPortableRooms.sorted { lhs, rhs in
            switch (lhs.ethernetEnabled, rhs.ethernetEnabled) {
            case (true, false): return true
            case (false, true): return false
            default:
                // If both are equal in ethernet priority, sort by model name
                let lhsModel = lhs.info?.model ?? ""
                let rhsModel = rhs.info?.model ?? ""
                return lhsModel.localizedStandardCompare(rhsModel) == .orderedDescending
            }
        }
        
        return sortedRooms.first ?? allRooms.first
    }
    
    public func setPriorityDevice() -> Room? {
        guard let device = priorityDevice() else { return nil }
        sonosSystemDiscoverService.sonosStorageIP.sonosIP = device.ip
        return device
    }
    
    public func setStaticIP(ip: String) async {
        sonosSystemDiscoverService.sonosStorageIP.sonosIP = ip
        try? await load(useCache: true)
    }
}



