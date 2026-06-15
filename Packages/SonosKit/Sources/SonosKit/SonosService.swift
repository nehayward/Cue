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
    @ObservationIgnored private var hasAppliedGroupsCache = false

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
        switch sortOption {
        case .nameAscending:
            groups.sorted(using: KeyPathComparator(\.coordinatorRoom.name))
        case .nameDescending:
            groups.sorted(using: KeyPathComparator(\.coordinatorRoom.name, order: .reverse))
        case .playing:
            groups.sorted { g1, g2 in
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
        // Copy each room's battery individually so a battery speaker (Move)
        // grouped under an AC coordinator (SPA) refreshes too. The earlier
        // filter on `coordinatorRoom.battery != nil` dropped the whole group
        // when the coordinator was AC-only, silently skipping the Move.
        for updateGroup in newGroup {
            guard let index = groups.firstIndex(where: { $0.coordinatorID == updateGroup.coordinatorID }) else { continue }
            syncBatteries(from: updateGroup, into: groups[index])
        }

        let newSig = Set(newGroup.map(\.topologyKey))
        let oldSig = Set(groups.map(\.topologyKey))
        if !newGroup.isEmpty, newSig != oldSig {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
            self.zones = OrderedDictionary(uniqueKeys: newGroup.map(\.coordinatorID), values: newGroup)
        }
    }

    public func updateHousehold() async throws {
        let newGroup = try await getGroups(useCache: true)

        // MARK: Update Battery Info — see `updateGroups()` for the why.
        for updateGroup in newGroup {
            guard let index = groups.firstIndex(where: { $0.coordinatorID == updateGroup.coordinatorID }) else { continue }
            syncBatteries(from: updateGroup, into: groups[index])
        }

        let newSig = Set(newGroup.map(\.topologyKey))
        let oldSig = Set(groups.map(\.topologyKey))
        if !newGroup.isEmpty, newSig != oldSig {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
            self.zones = OrderedDictionary(uniqueKeys: newGroup.map(\.coordinatorID), values: newGroup)
        }
    }

    public func group(with id: String) -> GroupRoom? {
        sorted.first(where: { $0.coordinatorID == id})
    }

    /// Copies battery state from a freshly-parsed `updateGroup` into the
    /// matching rooms of an already-stored `storedGroup`. Iterates every
    /// room — not just the coordinator — so a battery speaker (Move)
    /// grouped under an AC coordinator (SPA) doesn't get silently skipped.
    /// `coordinatorRoom` is touched explicitly in case it's a distinct
    /// reference from anything in `rooms`.
    private func syncBatteries(from updateGroup: GroupRoom, into storedGroup: GroupRoom) {
        for updateRoom in updateGroup.rooms {
            if let room = storedGroup.rooms.first(where: { $0.id == updateRoom.id }) {
                room.battery = updateRoom.battery
            }
        }
        storedGroup.coordinatorRoom.battery = updateGroup.coordinatorRoom.battery
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

        // MARK: Per-load state on existing groups — cheap field diffs + battery.
        // Capture class references rather than holding array indices across `await`s —
        // `groups` (and `group.rooms`) can be replaced or shrunk by other @MainActor work
        // during suspensions, leaving stale indices that crash with Array out-of-range.
        for updateGroup in newGroup {
            guard let group = groups.first(where: { $0.coordinatorID == updateGroup.coordinatorID }) else { continue }
            if group.coordinatorRoom.ethernetEnabled != updateGroup.coordinatorRoom.ethernetEnabled {
                group.coordinatorRoom.ethernetEnabled = updateGroup.coordinatorRoom.ethernetEnabled
            }
            if group.coordinatorRoom.micEnabled != updateGroup.coordinatorRoom.micEnabled {
                group.coordinatorRoom.micEnabled = updateGroup.coordinatorRoom.micEnabled
            }
            // Battery sync: every room, not just coordinator. See
            // `updateGroups()` for context on the SPA + Move case.
            syncBatteries(from: updateGroup, into: group)
        }

        let newSig = Set(newGroup.map(\.topologyKey))
        let oldSig = Set(groups.map(\.topologyKey))
        if !newGroup.isEmpty, newSig != oldSig, !isGrouping {
            await updateGroupsRooms(from: newGroup)
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
            applyGroupsCacheIfMatching()
            refreshGroup = true
            print("Refreshed")

            if !mediaServerHandler.deviceIP.isEmpty {
                // MARK: I don't want to block
                Task {
                    try await Task.sleep(for: .milliseconds(300))
                    onServerListening()
                }
            }
        }
        
        wakeSleepingRooms(rooms: rooms)

        // Refresh sleepTimer for every active coordinator (including the
        // selected group). Placed above the selectedGroup branch so the
        // scattered early returns below can't skip it — sleepTimer is
        // nil-gated, so retries every load until a coordinator resolves.
        await withTaskGroup(of: Void.self) { [weak self] taskGroup in
            guard let self = self else { return }
            for group in groups where group.coordinatorRoom.state == .active && group.coordinatorRoom.sleepTimer == nil {
                taskGroup.addTask { [weak self] in
                    guard let self = self else { return }
                    if let timer = await self.api.getSleepTimer(IP: group.coordinatorRoom.ip) {
                        group.coordinatorRoom.sleepTimer = timer
                    }
                }
            }
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

            guard var awaitedTrack = await track else {
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

            let previousArtwork = roomGroup.coordinatorRoom.track.artworkURL
            if previousArtwork != nil, roomGroup.coordinatorRoom.track.downloadedArtworkURL != previousArtwork {
                roomGroup.coordinatorRoom.track.downloadedArtworkURL = previousArtwork
            }

            // IMPORTANT: write through `roomGroup.coordinatorRoom.track.X` here,
            // not via a captured `let currentTrack`. Track is a struct — a
            // `let` capture is a value copy, so `currentTrack.field = newValue`
            // mutates the local copy and the room never sees the write.
            // (This was the silent cause of stale title/artist/artwork after
            // foreground when the new track shared `unique` with the prior
            // pulse's reconcile path, e.g. HLS radio metadata catching up.)
            if roomGroup.coordinatorRoom.track.unique == awaitedTrack.unique {
                if !roomGroup.isEditingPlayback,
                   roomGroup.coordinatorRoom.playbackPosition != awaitedTrack.playbackPosition {
                    roomGroup.coordinatorRoom.updatePlaybackPosition(awaitedTrack.playbackPosition)
                }
                if roomGroup.coordinatorRoom.track.position != awaitedTrack.position {
                    roomGroup.coordinatorRoom.track.position = awaitedTrack.position
                }
                // Sonos's HLS/radio metadata for Apple Music can lag — title/trackID
                // land before albumArtist/creator. Reconcile artist/album on later
                // pulses so a stale value doesn't stick forever. Gate on non-empty
                // so a missing field doesn't clobber known data.
                if !awaitedTrack.artist.isEmpty, roomGroup.coordinatorRoom.track.artist != awaitedTrack.artist {
                    roomGroup.coordinatorRoom.track.artist = awaitedTrack.artist
                }
                if !awaitedTrack.album.isEmpty, roomGroup.coordinatorRoom.track.album != awaitedTrack.album {
                    roomGroup.coordinatorRoom.track.album = awaitedTrack.album
                }
                return
            }

            // Only get track information if the track ID has changed
            let shouldGetTrackInfo = roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique
            
            if shouldGetTrackInfo {
                // Sonos's XML (`dc:title`, `dc:creator`, `r:albumArtist`) already gives us
                // displayable name/artist — assign immediately so the row never sits blank
                // while we wait on `getTrackInformation` (which can be slow or rate-limited
                // for Spotify/Apple Music). Metadata then enhances the track in place.
                //
                // Same-album carry: if the new track is on the same album, inherit the
                // existing artwork URL so ArtworkView's artworkURL never briefly becomes
                // the Sonos proxy (or nil) before the CDN URL arrives. Spotify sends only
                // dc:creator (per-track artist), so without this the URL changes twice on
                // every track change within an album, causing a visible flash.
                if !awaitedTrack.album.isEmpty,
                   awaitedTrack.album == roomGroup.coordinatorRoom.track.album,
                   let priorURL = roomGroup.coordinatorRoom.track.downloadedArtworkURL {
                    awaitedTrack.downloadedArtworkURL = priorURL
                }
                let hasDisplayableInfo = !awaitedTrack.name.isEmpty || !awaitedTrack.artist.isEmpty
                if hasDisplayableInfo {
                    roomGroup.coordinatorRoom.track = awaitedTrack
                }

                guard let (trackMetadata, artworkURL) = await self.getTrackInformation(from: awaitedTrack) else {
                    // Metadata fetch failed. If Sonos gave us nothing, bail — keep prior track.
                    guard hasDisplayableInfo else { return }
                    if !roomGroup.isEditingPlayback {
                        roomGroup.coordinatorRoom.updatePlaybackPosition(awaitedTrack.playbackPosition)
                    }
                    return
                }

                awaitedTrack.metadata = trackMetadata
                awaitedTrack.downloadedArtworkURL = artworkURL

                if awaitedTrack.musicService == .tuneIn {
                    awaitedTrack.artist = trackMetadata?.artist ?? ""
                }

                // If Sonos was empty earlier, this is our first chance to assign.
                if !hasDisplayableInfo {
                    roomGroup.coordinatorRoom.track = awaitedTrack
                }

                // Compare against the on-screen track — not `awaitedTrack`, which
                // already holds `artworkURL` from the line above, making this
                // check always false. Guard on `unique` so a track the user
                // skipped past during the slow lookup isn't clobbered.
                if roomGroup.coordinatorRoom.track.unique == awaitedTrack.unique {
                    roomGroup.coordinatorRoom.track.metadata = trackMetadata
                    if roomGroup.coordinatorRoom.track.downloadedArtworkURL != artworkURL {
                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                    }
                }
            } else {
                if !roomGroup.isEditingPlayback, isNowPlaying {
                    roomGroup.coordinatorRoom.updatePlaybackPosition(awaitedTrack.playbackPosition)
                }
            }

            if roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique {
                roomGroup.coordinatorRoom.track = awaitedTrack
                roomGroup.coordinatorRoom.track.downloadedArtworkURL = awaitedTrack.downloadedArtworkURL
            }

            Task {
                await ArtworkManager.shared.downScale(coordinatorRoom: roomGroup.nameWithCount, url: roomGroup.coordinatorRoom.track.artworkURL, trackID: roomGroup.coordinatorRoom.track.unique)
            }

            saveGroupsCache()
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

        // Hydrate deviceInfo + settings for any newly-added rooms. Runs after
        // the priority speaker-state updates above. SleepTimer is handled
        // inside the selectedGroup branch (it's a coordinator-level setting
        // only surfaced by the controlling group).
        await hydrateRoomDetails()
    }

    /// Fetches `DeviceInfo` and speaker `settings` in parallel for every active
    /// room across all groups. Used by `load()` after a topology change, and
    /// callable directly from the onboarding screen to pre-warm rows so the
    /// model name lands before the user reaches "Continue".
    ///
    /// Both fields are nil/`!isSet`-gated and never cleared, so this is
    /// effectively one-shot per room — repeated calls during steady state are
    /// no-ops. `coordinatorRoom` is the same reference as one of the entries
    /// in `group.rooms`, so a single pass covers it without duplicating.
    @MainActor
    public func hydrateRoomDetails() async {
        await withTaskGroup(of: Void.self) { [weak self] taskGroup in
            guard let self = self else { return }
            for group in groups where group.coordinatorRoom.state == .active {
                for room in group.rooms {
                    if room.info == nil {
                        taskGroup.addTask { [weak self] in
                            guard let self = self else { return }
                            room.info = await self.api.deviceInfo(IP: room.ip)
                        }
                    }
                    if !room.settings.isSet {
                        taskGroup.addTask { [weak self] in
                            guard let self = self else { return }
                            room.settings = await self.getSpeakerSettings(room: room)
                        }
                    }
                }
            }
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
                group.addTask { @MainActor [weak self] in
                    try? await self?.updateTrackInformation(for: [roomGroup])
                }

                group.addTask { @MainActor [weak self] in
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
                    
                    if let queueTotalAwaited = try? await queueTotal, roomGroup.coordinatorRoom.queueTotal != queueTotalAwaited {
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
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    // MARK: Sleeping or Off
                    if roomGroup.coordinatorRoom.state != .active { return }
                    async let track = getTrack(ip: roomGroup.coordinatorRoom.ip)
                    async let mediaInfo = api.mediaInfo(ipAddress: roomGroup.coordinatorRoom.ip)

                    guard var awaitedTrack = await track else {
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
                        // Active speaker briefly returning empty is usually a transient —
                        // keep the previous track on screen, let the next pulse settle.
                        return
                    }

                    // See twin site in `load()` — Track is a struct, so a
                    // `let currentTrack = ...` capture is a value copy and
                    // mutations vanish. Write through the Room property
                    // directly so the @Observable setter actually fires.
                    if roomGroup.coordinatorRoom.track.unique == awaitedTrack.unique {
                        if !roomGroup.isEditingPlayback, roomGroup.coordinatorRoom.playbackPosition != awaitedTrack.playbackPosition {
                            roomGroup.coordinatorRoom.updatePlaybackPosition(awaitedTrack.playbackPosition)
                        }

                        if roomGroup.coordinatorRoom.track.position != awaitedTrack.position {
                            roomGroup.coordinatorRoom.track.position = awaitedTrack.position
                        }

                        // Sonos's HLS/radio metadata for Apple Music can lag — title/trackID
                        // land before albumArtist/creator. Reconcile artist/album on later
                        // pulses so a stale value doesn't stick forever. Gate on non-empty
                        // so a missing field doesn't clobber known data.
                        if !awaitedTrack.artist.isEmpty, roomGroup.coordinatorRoom.track.artist != awaitedTrack.artist {
                            roomGroup.coordinatorRoom.track.artist = awaitedTrack.artist
                        }
                        if !awaitedTrack.album.isEmpty, roomGroup.coordinatorRoom.track.album != awaitedTrack.album {
                            roomGroup.coordinatorRoom.track.album = awaitedTrack.album
                        }
                        return
                    }

                    // Sonos's XML already provides displayable name/artist — assign now so
                    // the row never sits blank waiting on `getTrackInformation`.
                    //
                    // Same-album carry: see twin site above.
                    if !awaitedTrack.album.isEmpty,
                       awaitedTrack.album == roomGroup.coordinatorRoom.track.album,
                       let priorURL = roomGroup.coordinatorRoom.track.downloadedArtworkURL {
                        awaitedTrack.downloadedArtworkURL = priorURL
                    }
                    let hasDisplayableInfo = !awaitedTrack.name.isEmpty || !awaitedTrack.artist.isEmpty
                    if hasDisplayableInfo {
                        roomGroup.coordinatorRoom.track = awaitedTrack
                    }

                    guard let (trackMetadata, artworkURL) = await getTrackInformation(from: awaitedTrack) else {
                        guard hasDisplayableInfo else { return }
                        if !roomGroup.isEditingPlayback {
                            roomGroup.coordinatorRoom.updatePlaybackPosition(awaitedTrack.playbackPosition)
                        }
                        return
                    }

                    awaitedTrack.metadata = trackMetadata
                    awaitedTrack.downloadedArtworkURL = artworkURL

                    if awaitedTrack.musicService == .tuneIn {
                        awaitedTrack.artist = trackMetadata?.artist ?? ""
                    }

                    if !hasDisplayableInfo {
                        roomGroup.coordinatorRoom.track = awaitedTrack
                    }

                    // The hasDisplayableInfo branch assigned the track early from
                    // Sonos's XML, so the enriched metadata and high-res artwork
                    // from getTrackInformation still have to be written back —
                    // otherwise the view stays on Sonos's low-res proxy art and
                    // never gets `metadata`. Guard on `unique`: getTrackInformation
                    // is slow and the user may have skipped past this track.
                    if roomGroup.coordinatorRoom.track.unique == awaitedTrack.unique {
                        roomGroup.coordinatorRoom.track.metadata = trackMetadata
                        if roomGroup.coordinatorRoom.track.downloadedArtworkURL != artworkURL {
                            roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                        }
                    }

                    Task {
                        await ArtworkManager.shared.downScale(coordinatorRoom: roomGroup.nameWithCount, url: roomGroup.coordinatorRoom.track.artworkURL, trackID: roomGroup.coordinatorRoom.track.trackID)
                    }

                    self.saveGroupsCache()
                }
            }
        }
    }

    @MainActor
    public func updateGroupsRooms(from roomGroups: [GroupRoom]) async {
        await withDiscardingTaskGroup { group in
            for roomGroup in roomGroups {
                for room in roomGroup.rooms {
                    group.addTask { @MainActor [weak self] in
                        if room.state != .active { return }
                        guard let self else { return }
                        if let volume = try? await getVolume(ip: room.ip), !room.isEditingVolume {
                            room.volume = volume
                        }
                    }

                    group.addTask { @MainActor [weak self] in
                        if room.state != .active { return }
                        guard let self else { return }
                        if let isMuted = await api.getRoomMute(IP: room.ip) {
                            room.isMuted = isMuted
                        }
                    }

                    // MARK: Check Alarm
                    group.addTask { @MainActor [weak self] in
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
                group.addTask { @MainActor [weak self] in
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
        // Guard on topology only — comparing full GroupRoom equality includes
        // Track content and would fire on essentially every call, replacing
        // `self.groups` from a fresh-from-XML snapshot with empty tracks.
        let newSig = Set(newGroup.map(\.topologyKey))
        let oldSig = Set(groups.map(\.topologyKey))
        if !newGroup.isEmpty, newSig != oldSig {
            self.groups = newGroup
            self.rooms = newGroup.flatMap(\.rooms)
        }

        await withDiscardingTaskGroup { group in
            for (_, roomGroup) in groups.enumerated() {
                group.addTask { @MainActor [weak self] in
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

                group.addTask { @MainActor [weak self] in
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
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    if roomGroup.coordinatorRoom.state == .active, let isMuted = await self.isMuted(for: roomGroup) {
                        if roomGroup.isMuted != isMuted {
                            roomGroup.isMuted = isMuted
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
                group.addTask { @MainActor [weak self] in
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

                    guard var awaitedTrack = await track else { return }

                    guard let artworkURL = await self.getArtwork(from: awaitedTrack, size: 200) else {
                        if roomGroup.coordinatorRoom.track.unique != awaitedTrack.unique {
                            roomGroup.coordinatorRoom.track = awaitedTrack
                        }
                        roomGroup.coordinatorRoom.updatePlaybackPosition(awaitedTrack.playbackPosition)
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
                    }
                    roomGroup.coordinatorRoom.updatePlaybackPosition(awaitedTrack.playbackPosition)
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

    /// Fetches `DeviceInfo` for a Sonos speaker at the given IP. Useful for
    /// callers that want metadata (model name, swGen — S1 vs S2, capabilities)
    /// for a household other than the currently-monitored one, without having
    /// to switch over and wait for a full pulse.
    public func deviceInfo(for ip: String) async -> DeviceInfo? {
        await api.deviceInfo(IP: ip)
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
        // Get current groups, fallback to fetching them if necessary
        guard let currentGroups = !sorted.isEmpty ? sorted : try? await getGroupsFast() else {
            // Offline
            return nil
        }

        // If there's only one room, ungroup it and return as a single group
        if rooms.count == 1, let room = rooms.first {
            if let group = currentGroups.first(where: { $0.coordinatorRoom.id == room.id }), group.rooms.count == 1 {
                return group
            }
            await api.ungroup(IP: room.ip)
            return room.toGroup
        }

        let selectedIDs = Set(rooms.map(\.id))

        // Groups that overlap with the selection
        let relevantGroups = currentGroups.filter { group in
            group.rooms.contains(where: { selectedIDs.contains($0.id) })
        }

        // Refresh playback state for relevant groups so we can prefer a playing coordinator
        for group in relevantGroups {
            let playback = await getPlaybackInfo(ip: group.ip)
            group.coordinatorRoom.isPlaying = (playback == .playing)
        }

        // Pick a coordinator without ever bailing out:
        //   1. Playing group whose coordinator is in the selection (keeps playback)
        //   2. Any group whose coordinator is in the selection
        //   3. First selected room (becomes a new coordinator)
        let coordinatorRoom: Room
        if let playingInSelection = relevantGroups.first(where: { $0.coordinatorRoom.isPlaying && selectedIDs.contains($0.coordinatorID) }) {
            coordinatorRoom = playingInSelection.coordinatorRoom
        } else if let existing = relevantGroups.first(where: { selectedIDs.contains($0.coordinatorID) }) {
            coordinatorRoom = existing.coordinatorRoom
        } else if let first = rooms.first {
            coordinatorRoom = first
        } else {
            return nil
        }

        let coordinatorID = coordinatorRoom.id
        let targetGroup = currentGroups.first(where: { $0.coordinatorID == coordinatorID })
        let currentMembers = Set(targetGroup?.rooms.map(\.id) ?? [coordinatorID])

        // Diff added/removed (mirror smartGroup's set-based approach)
        let addedRooms = rooms.filter { $0.id != coordinatorID && !currentMembers.contains($0.id) }
        let removedRooms = (targetGroup?.rooms ?? []).filter { $0.id != coordinatorID && !selectedIDs.contains($0.id) }

        isGrouping = true

        // Eager local state updates so the UI reflects the new topology immediately
        for room in addedRooms {
            for group in groups {
                group.rooms.removeAll(where: { $0.id == room.id })
            }
            if let groupIndex = groups.firstIndex(where: { $0.coordinatorID == coordinatorID }) {
                if !groups[groupIndex].rooms.contains(where: { $0.id == room.id }) {
                    groups[groupIndex].rooms.append(room)
                }
            } else {
                // Coordinator wasn't itself a group yet — create one
                groups.append(coordinatorRoom.toGroup)
                if let groupIndex = groups.firstIndex(where: { $0.coordinatorID == coordinatorID }) {
                    groups[groupIndex].rooms.append(room)
                }
            }
            groups.removeAll(where: { $0.coordinatorID == room.id })
        }

        for room in removedRooms {
            if let groupIndex = groups.firstIndex(where: { $0.coordinatorID == coordinatorID }) {
                groups[groupIndex].rooms.removeAll { $0.id == room.id }
            }
            if !groups.contains(where: { $0.coordinatorID == room.id }) {
                groups.append(room.toGroup)
            }
        }

        // Network calls after local state updates
        for room in addedRooms {
            await api.group(IP: room.ip, to: coordinatorID)
        }
        for room in removedRooms {
            await api.ungroup(IP: room.ip)
        }

        isGroupingTask.cancel()
        isGroupingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(3.5))
            if Task.isCancelled { return }
            isGrouping = false
        }

        return groups.first(where: { $0.coordinatorID == coordinatorID }) ?? coordinatorRoom.toGroup
    }

    public func smartGroup(rooms: [Room], oldRooms: [Room], to group: GroupRoom) async -> String? {
        var newCoordinatorID: String? = nil

        isGrouping = true
        let newRoomIDs = Set(rooms.map(\.id))
        let oldRoomIDs = Set(oldRooms.map(\.id))

        // Determine the rooms that have been added
        let addedRooms = rooms.filter { !oldRoomIDs.contains($0.id) }

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
        let removedRooms = oldRooms.filter { !newRoomIDs.contains($0.id) }
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
        guard var track = await api.getCurrentTrack(ipAddress: ip, prioritizedAlbumArtIP: prioritizedIP()) else { return nil }
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
        var track = track
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
        case (.artist, .apple):
            guard let artist: Artist = try? await musicSearch.lookup(id: content.id) else { return nil }
            return PlayableContent(title: artist.name, subtitle: "", thumbnail: artist.artwork?.url(width: 100, height: 100), artwork: artist.artwork?.url(width: 500, height: 500), content: content)
        case (.artist, .spotify):
            guard let artist = await musicSearch.spotifyArtist(id: content.id) else { return nil }
            return PlayableContent(title: artist.name, subtitle: "", thumbnail: artist.images.thumbnail, artwork: artist.images.biggestImageURL, content: content)
        case (.radio, .apple):
            // Apple Music stations have no catalog lookup (`ra.u-*` IDs aren't
            // catalog items). Derive a name from `/station/<slug>/<id>` so the
            // room picker has something to show.
            let title = Self.appleStationTitle(from: url) ?? ""
            return PlayableContent(title: title, subtitle: "Station", thumbnail: nil, artwork: nil, content: content)
        default:
            return nil
        }
    }

    private static func appleStationTitle(from url: URL) -> String? {
        guard url.host?.contains("music.apple.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[1] == "station" else { return nil }
        let slug = parts[2].replacingOccurrences(of: "-", with: " ")
        return slug.isEmpty ? nil : slug.capitalized
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

    @MainActor
    public func pause(ip: String) async {
        if let group = groups.first(where: { $0.coordinatorRoom.ip == ip }) {
            for room in group.rooms {
                room.isPlaying = false
            }
            group.coordinatorRoom.isPlaying = false
        }

        isEditing = true
        await api.pause(ipAddress: ip)
        try? await Task.sleep(for: .milliseconds(400))
        isEditing = false
    }

    @MainActor
    public func play(ip: String) async {
        if let group = groups.first(where: { $0.coordinatorRoom.ip == ip }) {
            for room in group.rooms {
                room.isPlaying = true
            }
            group.coordinatorRoom.isPlaying = true
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

    /// Probes every group's coordinator concurrently and returns the first one
    /// reporting `.playing`, cancelling the rest. Falls back to a group in TV
    /// mode if nothing is playing. Used by deeplinks/speedlaunch to avoid
    /// routing on stale `isPlaying` state.
    @MainActor
    public func firstPlayingGroup() async -> GroupRoom? {
        let playing = await withTaskGroup(of: GroupRoom?.self) { taskGroup -> GroupRoom? in
            for roomGroup in groups {
                taskGroup.addTask {
                    let status = await self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
                    return status == .playing ? roomGroup : nil
                }
            }
            for await result in taskGroup where result != nil {
                taskGroup.cancelAll()
                return result
            }
            return nil
        }
        return playing ?? groups.first(where: \.TVMode)
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

    /// Sets a sleep timer that ends when the currently playing track finishes.
    /// Fetches the live playback position so the timer length matches the
    /// song's remaining time. Returns the duration applied, or `nil` when
    /// nothing is playing or the track has no known length (e.g. a radio
    /// stream, where `duration` is zero).
    @discardableResult
    public func sleepAtEndOfTrack(group: GroupRoom) async -> Duration? {
        guard let track = await getTrack(ip: group.ip) else { return nil }
        let remaining = track.timeRemaining
        guard remaining > .zero else { return nil }
        await sleepTimer(group: group, duration: remaining)
        return remaining
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

        if [.favorite, .radio, .liveRadio].contains(playable.content.type) {
            try await api.setAVTransportContent(playableContent: playable, IP: group.ip)
            return
        }
        
        if [.artistRadio, .songRadio].contains(playable.content.type) {
            try await api.startRadio(playableContent: playable, IP: group.ip)
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

    /// One-shot, run on first launch only: if persisted topology matches current groups,
    /// seed each coordinator room's track from the cache so the row paints immediately
    /// instead of waiting for the first network pulse to populate.
    @MainActor
    func applyGroupsCacheIfMatching() {
        guard !hasAppliedGroupsCache else { return }
        hasAppliedGroupsCache = true
        guard !groups.isEmpty, let cache = GroupsCacheStore.read() else { return }

        let liveSig = Set(groups.map(\.topologyKey))
        guard liveSig == cache.topologySignature else { return }

        for cached in cache.groups {
            guard let group = groups.first(where: { $0.coordinatorID == cached.coordinatorID }),
                  group.coordinatorRoom.track.name.isEmpty else { continue }

            var track = Track(
                trackID: cached.trackID,
                name: cached.trackName,
                artist: cached.trackArtist,
                album: cached.trackAlbum,
                musicService: cached.trackMusicService,
                duration: cached.trackDuration,
                sonosAlbumArtURL: cached.trackSonosAlbumArtURL
            )
            track.downloadedArtworkURL = cached.trackArtworkURL
            group.coordinatorRoom.track = track
        }
    }

    /// Persist current groups + per-coordinator track snapshot to disk.
    @MainActor
    func saveGroupsCache() {
        let snapshots = groups.map { group in
            CachedGroup(
                coordinatorID: group.coordinatorID,
                memberRoomIDs: group.rooms.map(\.id).sorted(),
                trackID: group.coordinatorRoom.track.trackID,
                trackName: group.coordinatorRoom.track.name,
                trackArtist: group.coordinatorRoom.track.artist,
                trackAlbum: group.coordinatorRoom.track.album,
                trackArtworkURL: group.coordinatorRoom.track.downloadedArtworkURL,
                trackSonosAlbumArtURL: group.coordinatorRoom.track.sonosAlbumArtURL,
                trackMusicService: group.coordinatorRoom.track.musicService,
                trackDuration: group.coordinatorRoom.track.duration
            )
        }
        GroupsCacheStore.write(GroupsCache(groups: snapshots))
    }
}



