import Foundation
import Observation
import SwiftUI
import CloudKit
import os


@Observable
@MainActor
public final class SonosMiniService {
    // `let` so the singleton can never be swapped out — reassigning it would leak
    // the old instance wholesale (streaming service, sockets, long-running tasks).
    public static let shared = SonosMiniService()
    
    public var devices: [SonosDevice] = []
    
    public var activeDevices: [SonosDevice] {
        get {
            devices.sorted { $0.name < $1.name }.filter(\.isVisible)
        } set {
            devices = newValue
        }
    }
    
    public var sorted: [SonosDevice] {
        get {
            let sorted = devices.sorted { $0.name < $1.name }
            return sorted
        } set {
            devices = newValue
        }
    }
    
    public var sortedNowPlaying: [SonosDevice] {
        get {
            let sorted = devices.sorted { g1, g2 in
                if g1.isPlaying != g2.isPlaying {
                    return g1.isPlaying && !g2.isPlaying
                }
                return g1.name < g2.name
            }
            return sorted
        } set {
            devices = newValue
        }
    }
    
    //    @ObservationIgnored private let sonosMonitor = SonosMonitor.shared
    @ObservationIgnored private lazy var discoveryService = SonosSystemDiscoveryService()
    // Callback for track changes
    @ObservationIgnored public var onTrackChanged: ((SonosDevice, SonosTrack) -> Void)?
    @ObservationIgnored private lazy var api = SonosAPI()
    /// Address published by the main app (or entered by hand on the Watch).
    /// Clic Mini has never written this key, only read it.
    @ObservationIgnored private var storedIP: String {
        NSUbiquitousKeyValueStore.default.string(forKey: "sonos_ip")
            ?? UserDefaults.standard.string(forKey: "sonos_ip")
            ?? ""
    }

    /// Address found by Bonjour discovery this session. Only consulted when
    /// `storedIP` is empty or has stopped answering, so an address the user
    /// enters explicitly always takes precedence over one we guessed.
    @ObservationIgnored private var resolvedIP: String?

    /// Address that most recently failed to answer. Recorded rather than erased
    /// so a stale stored value can be stepped past without discarding it — if the
    /// speaker comes back at that address it gets used again.
    @ObservationIgnored private var unreachableIP: String?

    /// In-flight discovery, shared by concurrent callers. `discoverDevices`
    /// rejects overlapping searches outright, so without this the second caller
    /// would fail rather than wait.
    @ObservationIgnored private var ipResolutionTask: Task<String, Never>?

    /// When discovery last came back empty. A failed search burns the full
    /// timeout, and callers such as `getNowPlayingID` retry freely, so failures
    /// are rate limited instead of stalling every request that follows.
    @ObservationIgnored private var lastFailedDiscovery: Date?

    private static let discoveryRetryInterval: TimeInterval = 30

    @ObservationIgnored private var cachedIP: String {
#if DEBUG
        return "192.168.4.153"
#else
        let stored = storedIP
        if !stored.isEmpty, stored != unreachableIP { return stored }
        return resolvedIP ?? stored
#endif

    }
    
    @ObservationIgnored public lazy var streamingService = SonosStreamingService(eventHandler: self)
    @ObservationIgnored var lastKnownGroupIDs: Set<String> = []

    // Tracked tasks to prevent unbounded task accumulation (memory leak fix).
    // Metadata tasks are keyed by playerId so events from different speakers don't
    // cancel each other — that was dropping queueTotal updates for all but the last
    // speaker to receive an event.
    @ObservationIgnored var metadataUpdateTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var groupUpdateTask: Task<Void, any Error>?
    @ObservationIgnored private var loadWatchInFlight: Task<Void, any Error>?

    @ObservationIgnored private var hasAppliedDevicesCache = false

    /// Callback invoked every 24 hours for app-level cache cleanup (e.g. image caches).
    /// Set this from the app layer since SonosKitMini doesn't know about Kingfisher/Nuke.
    @ObservationIgnored public var onPeriodicCleanup: (() -> Void)?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    /// Start a repeating 24-hour cleanup timer. Call once after initial setup.
    public func startPeriodicCleanup() {
        guard cleanupTask == nil else { return }
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60 * 60 * 24))
                } catch { break }
                guard let self else { break }
                self.onPeriodicCleanup?()
                // Trim device data that can re-accumulate
                for index in self.devices.indices {
                    self.devices[index].queue.removeAll()
                }
            }
        }
    }
    
    public func updateHousehold() async throws {
        let newDevices = try await getDevices(useCache: true)
        
        // MARK: Update Battery Info
        for device in newDevices.filter({ $0.battery != nil }) {
            guard let index = devices.firstIndex(of: device) else { continue }
            devices[index].battery = device.battery
        }
        
        if !newDevices.isEmpty && Set(newDevices) != Set(self.devices) {
            // Clear rooms arrays from old devices before replacement
            for index in devices.indices {
                devices[index].rooms.removeAll()
            }
            self.devices = newDevices
        }
    }
    
    @MainActor
    public func updateDevice<T: Equatable>(_ device: SonosDevice, keyPath: WritableKeyPath<SonosDevice, T>, value: T) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        if devices[index][keyPath: keyPath] != value {
            devices[index][keyPath: keyPath] = value
        }
    }

    /// Find a speaker by ID across all devices and their rooms
    public func speaker(for id: String) -> SonosDevice? {
        for device in devices {
            if device.id == id { return device }
            if let room = device.rooms.first(where: { $0.id == id }) { return room }
        }
        return nil
    }

    /// Update a speaker's volume by ID (coordinator or room member)
    public func updateSpeakerVolume(id: String, volume: Int) {
        // Update top-level device
        if let i = devices.firstIndex(where: { $0.id == id }) {
            if devices[i].volume != volume { devices[i].volume = volume }
        }
        // Also update any room copies inside other devices
        for i in devices.indices {
            if let j = devices[i].rooms.firstIndex(where: { $0.id == id }) {
                if devices[i].rooms[j].volume != volume { devices[i].rooms[j].volume = volume }
            }
        }
    }

    /// Update a speaker's mute state by ID (coordinator or room member)
    public func updateSpeakerMute(id: String, muted: Bool) {
        // Update top-level device
        if let i = devices.firstIndex(where: { $0.id == id }) {
            if devices[i].isMuted != muted { devices[i].isMuted = muted }
        }
        // Also update any room copies inside other devices
        for i in devices.indices {
            if let j = devices[i].rooms.firstIndex(where: { $0.id == id }) {
                if devices[i].rooms[j].isMuted != muted { devices[i].rooms[j].isMuted = muted }
            }
        }
    }
    
    func updateZone(event: SonosZoneEvent) {
        if case let .addGroup(deviceID, newID) = event {
            guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
            guard let newIndex = devices.firstIndex(where: { $0.id == newID }) else { return }
            // Check if already in rooms to prevent duplicate accumulation
            if devices[index].rooms.contains(where: { $0.id == newID }) {
                return
            }
            devices[index].rooms.append(devices[newIndex])
        }
        
        if case let .removeFromGroups(deviceId) = event {
            // Remove device from all groups' rooms arrays
            for (offset, _) in devices.enumerated() {
                // Use removeAll with closure for efficient removal if device appears multiple times
                devices[offset].rooms.removeAll(where: { $0.id == deviceId })
            }
        }
        
    }
    
    @MainActor
    func updateEvent(for deviceId: String, event: SonosServiceEvent) {
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        
        var device = devices[index]
        var changed = false
        
        switch event {
        case .groupRenderingControl(let renderingEvent):
            if let volume = renderingEvent.groupVolume, !device.isEditingVolume {
                changed = changed || device.groupVolume != Double(volume)
                device.groupVolume = Double(volume)
            }
            
            let groupIsMuted = renderingEvent.groupMute ?? false
            if device.groupIsMuted != groupIsMuted {
                device.groupIsMuted = groupIsMuted
                changed = true
            }
            
            if device.groupVolumeChangeable != renderingEvent.groupVolumeChangeable {
                device.groupVolumeChangeable = renderingEvent.groupVolumeChangeable
                changed = true
            }
            
        case .avTransport(let avEvent):
            if let actions = avEvent.currentTransportActions {
                let available = AvailableActions(
                    actions.components(separatedBy: ",").compactMap(AvailableActions.init)
                )
                if device.availableActions != available {
                    device.availableActions = available
                    changed = true
                }
            }
            
            if device.isAlarmRunning != avEvent.isAlarmRunning {
                device.isAlarmRunning = avEvent.isAlarmRunning
                changed = true
            }
            
            if device.queueTotal != avEvent.queueTotal {
                device.queueTotal = avEvent.queueTotal
                changed = true
            }
            
            let isHidden = avEvent.currentTrackURI.contains("x-rincon:RINCON")
            if device.isHidden != isHidden {
                device.isHidden = isHidden
                changed = true
            }
            
            if device.trackID != avEvent.trackID {
                device.trackID = avEvent.trackID
                changed = true
            }
            
            if device.musicServiceType != avEvent.musicService {
                device.musicServiceType = avEvent.musicService
                changed = true
            }
            
            if device.currentTrackURI != avEvent.currentTrackURI {
                device.currentTrackURI = avEvent.currentTrackURI
                changed = true
            }
            
            if device.transportState != (avEvent.transportState ?? "") {
                device.transportState = avEvent.transportState ?? ""
                changed = true
            }
            
            if device.currentTrackMetadata != avEvent.currentTrackMetadata {
                device.currentTrackMetadata = avEvent.currentTrackMetadata
                changed = true
            }
            
            if device.currentTrackDuration != (avEvent.currentTrackDuration ?? "") {
                device.currentTrackDuration = avEvent.currentTrackDuration ?? ""
                changed = true
            }
            
            if device.isCrossfaded != avEvent.currentCrossfadeMode {
                device.isCrossfaded = avEvent.currentCrossfadeMode
                changed = true
            }
            
            if device.nextTrackURI != avEvent.nextTrackURI {
                device.nextTrackURI = avEvent.nextTrackURI
                changed = true
            }
            
            if device.nextTrackMetadata != avEvent.nextTrackMetadata {
                device.nextTrackMetadata = avEvent.nextTrackMetadata
                changed = true
            }
            
        case .renderingContrl(let renderingControl):
            if device.volume != renderingControl.masterVolume {
                device.volume = renderingControl.masterVolume
                changed = true
            }
            
            if device.isMuted != renderingControl.masterMute {
                device.isMuted = renderingControl.masterMute
                changed = true
            }
            
            if let nightMode = renderingControl.nightMode {
                let isArcUltra = device.isArcUltra
                let newSettings: SonosTVSettings
                if isArcUltra {
                    newSettings = SonosTVSettings(
                        nightMode: nightMode,
                        dialogLevel: false,
                        speechEnhanceEnabled: renderingControl.speechEnhanceEnabled ?? device.TVSettings?.speechEnhanceEnabled,
                        dialogLevelValue: renderingControl.dialogLevel ?? device.TVSettings?.dialogLevelValue ?? 1,
                        audioInputFormat: nil
                    )
                } else if let dialogLevel = renderingControl.dialogLevel {
                    newSettings = SonosTVSettings(
                        nightMode: nightMode,
                        dialogLevel: dialogLevel == 1,
                        audioInputFormat: nil
                    )
                } else {
                    newSettings = SonosTVSettings(
                        nightMode: nightMode,
                        dialogLevel: device.TVSettings?.dialogLevel ?? false,
                        audioInputFormat: nil
                    )
                }
                if device.TVSettings != newSettings {
                    device.TVSettings = newSettings
                    changed = true
                }
            }
            
        case .position(let position):
            if device.currentTime != position.relativeTime {
                device.currentTime = position.relativeTime
                changed = true
            }
            
        case .isPlaying(let isPlaying):
            let newState = isPlaying ? "PLAYING" : "PAUSED_PLAYBACK"
            if device.transportState != newState {
                device.transportState = newState
                changed = true
            }
            
            if device.isPlaying != isPlaying {
                device.isPlaying = isPlaying
                changed = true
            }
            
        case .progress(let date):
            if device.lastUpdate != date {
                device.lastUpdate = date
                changed = true
            }
            
        case .deviceProperties(let event):
            if device.battery != event.battery {
                device.battery = event.battery
                changed = true
            }
            
            if let name = event.name {
                let cleanName = name.ampersandSafe.replacingOccurrences(of: "%26", with: "&").replacingOccurrences(of: "&apos;", with: "'")
                if device.name != cleanName {
                    device.name = cleanName
                    changed = true
                }
            }
        }
        
        if changed {
            devices[index] = device
        }
    }
    
    //    public func stopMonitor() {
    //        sonosMonitor.listener.stopServer()
    //    }
    //
    public func load(useCache: Bool) async throws {
        //        let newGroups = try await getGroups(useCache: useCache)
        let newDevices = try await getDevices(useCache: useCache)
        
        // Change to direct array comparison since order is preserved
        let newDeviceIDs = newDevices.map({ $0.id })
        let currentDeviceIDs = devices.map({ $0.id })
        
        if !newDevices.isEmpty && Set(newDeviceIDs) != Set(currentDeviceIDs) {
            self.devices = newDevices
        }
        //        setupListeners()
        
        //        Task {
        //            await sonosMonitor.startListening()
        //            print("Started")
        //            sonosMonitor.subscriber.updateDevices(devices.map{ $0.ip })
        //            sonosMonitor.subscriber.subscribe()
        //        }
        //
        //        snapShotVolume(for: devices)
        
        
        //        // Check for new or changed devices
        //        if !newGroups.isEmpty, Set(newGroups) != Set(devices), !isGrouping {
        //            await updateGroupsRooms(from: newGroups)
        //            self.devices = newGroups
        //            self.rooms = newGroups.flatMap(\.rooms)
        //            refreshGroup = true
        //        }
        
        //        // Handle selected group updates
        //        if let selectedGroup, !refreshGroup {
        //            guard let groupIndex = devices.firstIndex(where: { $0.coordinatorID == selectedGroup.coordinatorID }),
        //                  devices[groupIndex].coordinatorRoom.state == .active else {
        //                self.selectedGroup = nil
        //                return
        //            }
        //            await updateSelectedGroup(devices[groupIndex], keyPaths: keyPaths)
        //        } else {
        //            try await updateGroups(from: devices)
        //            await updateGroupsRooms(from: devices)
        //        }
        
        //        try await updateDevices(from: devices)
        //        await checkTVMode(from: devices)
    }
    
    /// Coalesces concurrent callers onto a single in-flight load. Two overlapping
    /// runs used to race disconnectAll/addPlayers on topology changes, closing
    /// sockets the other run had just opened and orphaning connections.
    public func loadWatch(useCache: Bool) async throws {
        if let inFlight = loadWatchInFlight {
            try await inFlight.value
            return
        }
        let task = Task { try await performLoadWatch(useCache: useCache) }
        loadWatchInFlight = task
        defer { loadWatchInFlight = nil }
        try await task.value
    }

    private func performLoadWatch(useCache: Bool) async throws {
        let (newDevices, houseHoldID) = try await getSystem(useCache: useCache)
        let newDeviceIDs = newDevices.map({ $0.id })
        let currentDeviceIDs = devices.map({ $0.id })
        
        if !newDevices.isEmpty && Set(newDeviceIDs) != Set(currentDeviceIDs) {
            // Clear rooms arrays from old devices before replacement to prevent retention
            for index in devices.indices {
                devices[index].rooms.removeAll()
            }
            
            self.devices = newDevices

            // CRITICAL FIX: Disconnect all existing connections before adding new ones
            // This prevents accumulation of WebSocket connections and memory leaks
            await streamingService.disconnectAll()
        }

        applyDevicesCacheIfMatching()

        // Fetch device info in parallel so isArcUltra resolves correctly
        await withDiscardingTaskGroup { group in
            for device in devices where device.info == nil {
                group.addTask { [weak self] in
                    guard let self else { return }
                    if let info = await api.deviceInfo(IP: device.ip) {
                        await updateDevice(device, keyPath: \.info, value: info)
                    }
                }
            }
        }

        // MARK: Update Devices Info
        try await updateWatchDevices(from: devices)
        await updateRoomVolumes()

        let configs = devices.map { $0.toConfig(with: houseHoldID)}
        lastKnownGroupIDs = Set(devices.map(\.groupID))
        await streamingService.addPlayers(configs)
        
    }
    
    /// Cleanup method to explicitly release resources and prevent memory leaks
    /// Call this when you need to force cleanup of all connections and cached data
    public func cleanup() async {
        // Cancel tracked tasks to stop any in-flight work
        for task in metadataUpdateTasks.values { task.cancel() }
        metadataUpdateTasks.removeAll()
        groupUpdateTask?.cancel()
        groupUpdateTask = nil
        cleanupTask?.cancel()
        cleanupTask = nil
        loadWatchInFlight?.cancel()
        loadWatchInFlight = nil

        // Clear callbacks to prevent retain cycles
        onTrackChanged = nil
        onPeriodicCleanup = nil

        // Disconnect all streaming connections
        await streamingService.disconnectAll()

        // Clear all device data to free memory
        for index in devices.indices {
            devices[index].rooms.removeAll()
            devices[index].queue.removeAll()
        }

        // Clear devices array
        devices.removeAll()
    }
    
    @MainActor
    public func updateWatchDevices(from devices: [SonosDevice]) async throws {
        try await withThrowingDiscardingTaskGroup { taskGroup in
            taskGroup.addTask { [weak self] in
                guard let self else { return }
                try? await updateTracks(for: devices)
            }
            taskGroup.addTask { [weak self] in
                guard let self else { return }
                try? await updateMuteState(for: devices)
            }
            for device in devices {
                taskGroup.addTask { [weak self] in
                    guard let self else { return }
                    async let playbackInfo = getPlaybackInfo(ip: device.ip)
                    async let groupVolume = getGroupVolume(ip: device.ip)
                    async let availableActions = getCurrentTransportActions(ip: device.ip)
                    
                    switch await playbackInfo {
                    case .playing:
                        await updateDevice(device, keyPath: \.isPlaying, value: true)
                    case .paused:
                        await updateDevice(device, keyPath: \.isPlaying, value: false)
                    default:
                        break
                    }
                    
                    if let groupVolumeAwaited = try? await groupVolume, !device.isEditingVolume {
                        await updateDevice(device, keyPath: \.groupVolume, value: groupVolumeAwaited)
                    }
                    
                    if let awaitedActions = await availableActions {
                        await updateDevice(device, keyPath: \.availableActions, value: awaitedActions)
                    }
                }
            }
        }
    }
    
    public func updateRoomVolumes(incomingDevices: [SonosDevice]? = nil) async {
        await withDiscardingTaskGroup { taskGroup in
            for device in incomingDevices ?? devices {
                taskGroup.addTask { [weak self] in
                    guard let self else { return }
                    guard let index = await devices.firstIndex(where: { $0.id == device.id }) else {
                        return
                    }
                    if let volume = try? await getVolume(ip: device.ip) {
                        await updateDevice(devices[index], keyPath: \.volume, value: Int(volume))
                    }
                    return
                }
            }
        }
    }
    
    public func updateGroupVolume(incomingDevices: [SonosDevice]? = nil) async {
        await withDiscardingTaskGroup { taskGroup in
            for device in incomingDevices ?? devices {
                taskGroup.addTask { [weak self] in
                    guard let self else { return }
                    guard let index = await devices.firstIndex(where: { $0.id == device.id }) else {
                        return
                    }
                    if let groupVolume = try? await api.getGroupVolume(ipAddress: device.ip) {
                        await updateDevice(devices[index], keyPath: \.groupVolume, value: groupVolume)
                    }
                    return
                }
            }
        }
    }
    
    public func updateRoomMuteState(incomingDevices: [SonosDevice]? = nil) async {
        await withDiscardingTaskGroup { taskGroup in
            for device in incomingDevices ?? devices {
                taskGroup.addTask { [weak self] in
                    guard let self else { return }
                    guard let index = await devices.firstIndex(where: { $0.id == device.id }) else {
                        return
                    }
                    if let isMuted = await api.getDeviceMute(IP: device.ip) {
                        await updateDevice(devices[index], keyPath: \.isMuted, value: isMuted)
                    }
                    return
                }
            }
        }
    }
    
    public func getNowPlayingID() async -> String? {
        if devices.isEmpty {
            try? await updateDevices(useCache: true)
        }
        let playingID = try? await firstPlayingDeviceID(from: devices)
        return playingID
    }
    
    @MainActor
    public func updateTracks(for newDevices: [SonosDevice]) async throws {
        try await withThrowingDiscardingTaskGroup { taskGroup in
            for device in newDevices {
                taskGroup.addTask { [weak self] in
                    guard let self else { return }
                    async let track = getTrack(ip: device.ip)
                    guard let awaitedTrack = await track else {
                        return
                    }
                    
                    await updateDevice(device, keyPath: \.isHidden, value: awaitedTrack.trackURI.contains("x-rincon:RINCON"))
                    await updateDevice(device, keyPath: \.currentTrackURI, value: awaitedTrack.trackURI)
                    
                    if device.track != awaitedTrack {
                        await updateDevice(device, keyPath: \.track, value: awaitedTrack)
                        await self.saveDevicesCache()
                    }
                    
                    if awaitedTrack.trackURI.contains("x-sonos-htastream") {
                        if let settings = try? await getTVSettings(ip: device.ip) {
                            await updateDevice(device, keyPath: \.TVSettings, value: settings)
                        }
                    }
                    
                    if awaitedTrack.trackURI.contains("rincon") {
                        guard let groupWithId = awaitedTrack.trackURI.components(separatedBy: ":").last else { return }
                        guard let index = await devices.firstIndex(where: { $0.id == groupWithId }) else { return }
                        guard let newIndex = await devices.firstIndex(where: { $0.id == device.id }) else { return }
                        if await devices[index].rooms.contains(where: { $0.id == device.id }) {
                            return
                        }
                        
                        if let removalIndex = await devices[index].rooms.firstIndex(where: { $0.id == device.id }) {
                            var rooms = await devices[index].rooms
                            rooms.remove(at: removalIndex)
                            await updateDevice(devices[index], keyPath: \.rooms, value: rooms)
                        }
                        
                        var rooms = await devices[index].rooms
                        rooms.append(await devices[newIndex])
                        await updateDevice(devices[index], keyPath: \.rooms, value: rooms)
                    } else {
                        for (offset, _) in await devices.enumerated() {
                            guard let removalIndex = await devices[offset].rooms.firstIndex(where: { $0.id == device.id }) else { continue }
                            var rooms = await devices[offset].rooms
                            rooms.remove(at: removalIndex)
                            await updateDevice(devices[offset], keyPath: \.rooms, value: rooms)
                        }
                    }
                    return
                }
            }
        }
    }
    
    @MainActor
    public func updateMuteState(for newDevices: [SonosDevice]) async throws {
        try await withThrowingDiscardingTaskGroup { taskGroup in
            for device in newDevices.filter(\.isVisible) {
                taskGroup.addTask { [weak self] in
                    guard let self else { return }
                    guard let index = await devices.firstIndex(where: { $0.id == device.id }) else {
                        assertionFailure()
                        return
                    }
                    
                    if let isMuted = await api.getGroupMute(IP: device.ip) {
                        await updateDevice(devices[index], keyPath: \.groupIsMuted, value: isMuted)
                    }
                    return
                }
            }
        }
    }
    
    
    
    private func updateSelectedGroup(_ group: SonosGroup, keyPaths: Set<PartialKeyPath<SonosGroup>>) async {
        //        async let track = keyPaths.contains(\SonosGroup.track) ? getTrack(ip: group.coordinatorRoom.ip) : nil
        //        async let playbackInfo = keyPaths.contains(\SonosGroup.coordinatorRoom.isPlaying) ? getPlaybackInfo(ip: group.coordinatorRoom.ip) : nil
        //        async let groupVolume = keyPaths.contains(\SonosGroup.groupVolume) ? getGroupVolume(ip: group.coordinatorRoom.ip) : nil
        //        async let playMode = keyPaths.contains(\SonosGroup.playMode) ? self.playMode(ip: group.coordinatorRoom.ip) : nil
        //
        //        if keyPaths.contains(\Group.coordinatorRoom.isPlaying) {
        //            switch await playbackInfo {
        //            case .playing:
        //                group.coordinatorRoom.isPlaying = true
        //            case .paused:
        //                group.coordinatorRoom.isPlaying = false
        //            default:
        //                break
        //            }
        //        }
        //
        //        if let updatedVolume = try? await groupVolume, !group.isEditingVolume {
        //            group.groupVolume = updatedVolume
        //        }
        //
        //        if let awaitedTrack = await track, group.coordinatorRoom.track != awaitedTrack {
        //            group.coordinatorRoom.track = awaitedTrack
        //        }
        //
        //        if keyPaths.contains(\Group.playMode) {
        //            group.playMode = await playMode
        //        }
    }
    
    //    public func load(useCache: Bool) async throws {
    //        let newGroup = try await getGroups(useCache: useCache)
    
    
    //        // MARK: Update Battery Info And Other Room Information
    //        for updateGroup in newGroup {
    //            guard let index = devices.firstIndex(of: updateGroup) else { continue }
    //            devices[index].coordinatorRoom.ethernetEnabled = updateGroup.coordinatorRoom.ethernetEnabled
    //            devices[index].coordinatorRoom.micEnabled = updateGroup.coordinatorRoom.micEnabled
    //            devices[index].coordinatorRoom.battery = updateGroup.coordinatorRoom.battery
    //            if devices[index].coordinatorRoom.info == nil, updateGroup.coordinatorRoom.state == .active {
    //                print("Update device Info")
    //                // MARK: Update all rooms Info.
    //                devices[index].coordinatorRoom.info = await api.deviceInfo(IP: updateGroup.coordinatorRoom.ip)
    //            }
    //
    //            for roomIndex in devices[index].rooms.indices {
    //                if devices[index].rooms[roomIndex].info == nil, updateGroup.coordinatorRoom.state == .active {
    //                    devices[index].rooms[roomIndex].info = await api.deviceInfo(IP: devices[index].rooms[roomIndex].ip)
    //                }
    //
    //                guard !devices[index].rooms[roomIndex].settings.isSet else {
    //                    continue
    //                }
    //                devices[index].rooms[roomIndex].settings = await getSpeakerSettings(room: devices[index].rooms[roomIndex])
    //            }
    //        }
    //
    //        if !newGroup.isEmpty, Set(newGroup) != Set(devices), !isGrouping {
    //            await updateGroupsRooms(from: newGroup)
    //            self.devices = newGroup
    //            self.rooms = newGroup.flatMap(\.rooms)
    //            refreshGroup = true
    //            print("Refreshed")
    //            print("NewGroup \(newGroup.count), Old \(devices.count)")
    //            print("Set NewGroup \(Set(newGroup).count), Old \(Set(devices).count)")
    //
    //            print(isGrouping)
    //        }
    //
    //        await wakeSleepingRooms(rooms: rooms)
    //
    //        if let selectedGroup, !refreshGroup {
    //            guard let groupIndex = devices.firstIndex(where: { group in
    //                group.coordinatorID == selectedGroup.coordinatorID
    //            }) else {
    //                print("Group Changed")
    //                print(selectedGroup.coordinatorRoom.id)
    //                print(selectedGroup.coordinatorID)
    //                for group in devices {
    //                    print(group.coordinatorRoom.id)
    //                    print(group.coordinatorID)
    //                    print("")
    //                }
    //                self.selectedGroup = nil
    //                return
    //            }
    //            if selectedGroup.coordinatorRoom.state != .active { return }
    //
    //            let roomGroup = devices[groupIndex]
    //            if roomGroup != selectedGroup {
    //                self.selectedGroup = roomGroup
    //            }
    //            async let track = self.getTrack(ip: roomGroup.coordinatorRoom.ip)
    //            async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
    //            async let groupVolume = self.getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
    //            async let playMode = self.playMode(ip: roomGroup.coordinatorRoom.ip)
    //            async let availableActions = self.getCurrentTransportActions(ip: roomGroup.ip)
    //            await updateGroupCheckTVMode(from: [roomGroup])
    //
    //            guard !isEditing else { return }
    //
    //            switch await playbackInfo {
    //            case .playing:
    //                roomGroup.coordinatorRoom.isPlaying = true
    //            case .paused:
    //                roomGroup.coordinatorRoom.isPlaying = false
    //            default:
    //                break
    //            }
    //
    //            if let updateGroupVolume = try? await groupVolume, !roomGroup.isEditingVolume {
    //                roomGroup.groupVolume = updateGroupVolume
    //            }
    //
    //            if let awaitedActions = await availableActions {
    //                roomGroup.availableActions = awaitedActions
    //            }
    //
    //            await updateGroupsRooms(from: [roomGroup])
    //            await updateGroupMuteState(for: [roomGroup])
    //
    //            guard let awaitedTrack = await track else {
    //                return
    //            }
    //
    //            if awaitedTrack == .empty {
    //                if roomGroup.coordinatorRoom.track != .empty {
    //                    ArtworkManager.shared.removeArtwork(coordinatorRoom: roomGroup.nameWithCount)
    //                    roomGroup.coordinatorRoom.track = .empty
    //                    roomGroup.coordinatorRoom.track.downloadedArtworkURL = nil
    //                    roomGroup.coordinatorRoom.track.sonosAlbumArtURL = nil
    //                }
    //                return
    //            }
    //
    //            let previousArtwork = roomGroup.coordinatorRoom.track.artworkURL
    //            if previousArtwork != nil {
    //                roomGroup.coordinatorRoom.track.downloadedArtworkURL = previousArtwork
    //            }
    //
    //            if roomGroup.coordinatorRoom.track == awaitedTrack, !roomGroup.isEditingPlayback {
    //                roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
    //                return
    //            }
    
    // MARK: Debug
    //            print(roomGroup.coordinatorRoom.track.name, awaitedTrack.name)
    //            print(roomGroup.coordinatorRoom.track.position, awaitedTrack.position)
    //            print(roomGroup.coordinatorRoom.track.trackID, awaitedTrack.trackID)
    //            print("Load:", roomGroup.coordinatorRoom.name)
    
    //            guard let (trackMetadata, artworkURL) = await self.getTrackInformation(from: awaitedTrack) else {
    //                if roomGroup.coordinatorRoom.track != awaitedTrack {
    //                    roomGroup.coordinatorRoom.track = awaitedTrack
    //                } else if !roomGroup.isEditingPlayback {
    //                    roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
    //                }
    //                return
    //            }
    //
    //            roomGroup.playMode = await playMode
    //            awaitedTrack.downloadedArtworkURL = artworkURL
    //            awaitedTrack.metadata = trackMetadata
    //
    //            if artworkURL != awaitedTrack.artworkURL {
    //                roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
    //            }
    //
    //            if awaitedTrack.musicService == .tuneIn {
    //                awaitedTrack.artist = trackMetadata?.artist ?? ""
    //            }
    //
    //            if roomGroup.coordinatorRoom.track != awaitedTrack {
    //                roomGroup.coordinatorRoom.track = awaitedTrack
    //                roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
    //            }
    //            return
    //        }
    
    //        try await updateGroups(from: devices)
    //        await updateGroupsRooms(from: devices)
    //        await updateGroupCheckTVMode(from: devices)
    //        await updateGroupMuteState(for: devices)
    //
    
    public func updateDevices(from devicesToUpdate: [SonosDevice]) async throws {
        await withDiscardingTaskGroup { group in
            for device in devicesToUpdate {
                group.addTask { [weak self] in
                    guard let self else { return }
                    // MARK: Sleeping or Off
                    if device.state != .active { return }
                    
                    //                    async let playbackInfo = getPlaybackInfo(ip: device.ip)
                    async let groupVolume = getGroupVolume(ip: device.ip)
                    async let track = getTrack(ip: device.ip)
                    //                    async let playMode = playMode(ip: roomGroup.coordinatorRoom.ip)
                    async let availableActions = getCurrentTransportActions(ip: device.ip)
                    //                    async let _ = updateGroupMuteState(for: devices)
                    //
                    //                    let isPlaying = await playbackInfo.isPlaying
                    //                    lock.withLock { [weak self] in
                    //                        self?.devices[index].isPlaying = isPlaying
                    //                    }
                    //
                    if let groupVolumeAwaited = try? await groupVolume, !device.isEditingVolume {
                        await updateDevice(device, keyPath: \.groupVolume, value: groupVolumeAwaited)
                    }
                    
                    
                    
                    if let awaitedActions = await availableActions {
                        await updateDevice(device, keyPath: \.availableActions, value: awaitedActions)
                    }
                    
                    guard let awaitedTrack = await track else {
                        return
                    }
                    
                    // Removed print statement to prevent memory accumulation in hot path
                    // print(awaitedTrack)
                    
                    if device.track.id != awaitedTrack.id, !device.isEditingPlayback {
                        let newMetadata = SonosTrackMetadata(
                            title: awaitedTrack.name,
                            creator: awaitedTrack.artist,
                            album: awaitedTrack.album,
                            albumArtURI: awaitedTrack.albumArtURI,
                            streamInfo: nil
                        )
                        
                        // Update with the new metadata using updateDevice helper
                        await updateDevice(device, keyPath: \.currentTrackMetadata, value: newMetadata)
                        return
                    }
                    
                    //
                    //                    if awaitedTrack == .empty {
                    //                        if device.track != .empty {
                    //                            device.track = .empty
                    //                            device.track.downloadedArtworkURL = nil
                    //                            device.track.sonosAlbumArtURL = nil
                    //                        }
                    //                        return
                    //                    }
                    
                    //]
                    print(awaitedTrack)
                    
                    if device.track.id != awaitedTrack.id, !device.isEditingPlayback {
                        let newMetadata = SonosTrackMetadata(
                            title: awaitedTrack.name,
                            creator: awaitedTrack.artist,
                            album: awaitedTrack.album,
                            albumArtURI: awaitedTrack.albumArtURI,
                            streamInfo: nil
                        )
                        
                        // Update with the new metadata using the lock
                        await updateDevice(device, keyPath: \.currentTrackMetadata, value: newMetadata)
                        return
                    }
                    
                    //                    print(roomGroup.coordinatorRoom.track.name, awaitedTrack.name)
                    //                    print(roomGroup.coordinatorRoom.track.position, awaitedTrack.position)
                    //                    print(roomGroup.coordinatorRoom.track.trackID, awaitedTrack.trackID)
                    //                    print("UPDATEGROUP:", roomGroup.coordinatorRoom.name)
                    
                    //                    guard let (trackMetadata, artworkURL) = await getTrackInformation(from: awaitedTrack) else {
                    //                        if roomGroup.coordinatorRoom.track != awaitedTrack {
                    //                            roomGroup.coordinatorRoom.track = awaitedTrack
                    //                        } else if !roomGroup.isEditingPlayback {
                    //                            roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                    //                        }
                    //                        return
                    //                    }
                    //
                    //                    roomGroup.playMode = await playMode
                    //                    awaitedTrack.downloadedArtworkURL = artworkURL
                    //                    awaitedTrack.metadata = trackMetadata
                    //
                    //                    if awaitedTrack.musicService == .tuneIn {
                    //                        awaitedTrack.artist = trackMetadata?.artist ?? ""
                    //                    }
                    //
                    //                    if roomGroup.coordinatorRoom.track != awaitedTrack {
                    //                        lock.withLock { [weak self] in
                    //                            print(awaitedTrack)
                    //                            self?.devices[index].coordinatorRoom.track = awaitedTrack
                    //                        }
                    ////                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                    //                    }
                }
            }
        }
    }
    
    public func updateGroups(from devices: [SonosGroup]) async throws {
        await withDiscardingTaskGroup { group in
            for roomGroup in devices {
                group.addTask { [weak self] in
                    guard let self else { return }
                    // MARK: Sleeping or Off
                    if roomGroup.coordinatorRoom.state != .active { return }
                    //                    guard let index = self.devices.firstIndex(of: roomGroup) else { return }
                    //
                    //                    async let playbackInfo = getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
                    //                    async let groupVolume = getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
                    //                    async let track = getTrack(ip: roomGroup.coordinatorRoom.ip)
                    ////                    async let playMode = playMode(ip: roomGroup.coordinatorRoom.ip)
                    //                    async let availableActions = getCurrentTransportActions(ip: roomGroup.ip)
                    //                    async let _ = updateGroupMuteState(for: devices)
                    //
                    //                    let isPlaying = await playbackInfo.isPlaying
                    //                    lock.withLock { [weak self] in
                    //                        self?.devices[index].coordinatorRoom.isPlaying = isPlaying
                    //                    }
                    //
                    //                    if let groupVolumeAwaited = try? await groupVolume, !roomGroup.isEditingVolume {
                    //                        lock.withLock { [weak self] in
                    //                            self?.devices[index].groupVolume = groupVolumeAwaited
                    //                        }
                    //                    }
                    //
                    //                    if let awaitedActions = await availableActions {
                    //                        lock.withLock { [weak self] in
                    //                            self?.devices[index].availableActions = awaitedActions
                    //                        }
                    //                    }
                    ////
                    //                    guard let awaitedTrack = await track else {
                    //                        return
                    //                    }
                    
                    //                    if awaitedTrack == .empty {
                    //                        if roomGroup.coordinatorRoom.track != .empty {
                    //                            roomGroup.coordinatorRoom.track = .empty
                    //                            roomGroup.coordinatorRoom.track.downloadedArtworkURL = nil
                    //                            roomGroup.coordinatorRoom.track.sonosAlbumArtURL = nil
                    //                        }
                    //                        return
                    //                    }
                    //
                    ////
                    //                    if roomGroup.coordinatorRoom.track == awaitedTrack, !roomGroup.isEditingPlayback {
                    //                        lock.withLock { [weak self] in
                    //                            self?.devices[index].coordinatorRoom.track.duration = awaitedTrack.duration
                    //                        }
                    //                        return
                    //                    }
                    
                    //                    print(roomGroup.coordinatorRoom.track.name, awaitedTrack.name)
                    //                    print(roomGroup.coordinatorRoom.track.position, awaitedTrack.position)
                    //                    print(roomGroup.coordinatorRoom.track.trackID, awaitedTrack.trackID)
                    //                    print("UPDATEGROUP:", roomGroup.coordinatorRoom.name)
                    
                    //                    guard let (trackMetadata, artworkURL) = await getTrackInformation(from: awaitedTrack) else {
                    //                        if roomGroup.coordinatorRoom.track != awaitedTrack {
                    //                            roomGroup.coordinatorRoom.track = awaitedTrack
                    //                        } else if !roomGroup.isEditingPlayback {
                    //                            roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
                    //                        }
                    //                        return
                    //                    }
                    //
                    //                    roomGroup.playMode = await playMode
                    //                    awaitedTrack.downloadedArtworkURL = artworkURL
                    //                    awaitedTrack.metadata = trackMetadata
                    //
                    //                    if awaitedTrack.musicService == .tuneIn {
                    //                        awaitedTrack.artist = trackMetadata?.artist ?? ""
                    //                    }
                    //
                    //                    if roomGroup.coordinatorRoom.track != awaitedTrack {
                    //                        lock.withLock { [weak self] in
                    //                            print(awaitedTrack)
                    //                            self?.devices[index].coordinatorRoom.track = awaitedTrack
                    //                        }
                    ////                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
                    //                    }
                }
            }
        }
    }
    //
    //    @MainActor
    //    public func updateGroupsRooms(from roomGroups: [GroupRoom]) async {
    //        await withDiscardingTaskGroup { group in
    //            for roomGroup in roomGroups {
    //                for room in roomGroup.rooms {
    //                    group.addTask { [weak self] in
    //                        if room.state != .active { return }
    //                        guard let self else { return }
    //                        if let volume = try? await getVolume(ip: room.ip), !room.isEditingVolume {
    //                            room.volume = volume
    //                        }
    //                    }
    //
    //                    group.addTask { [weak self] in
    //                        if room.state != .active { return }
    //                        guard let self else { return }
    //                        if let isMuted = await api.getRoomMute(IP: room.ip) {
    //                            room.isMuted = isMuted
    //                        }
    //                    }
    //
    //                    // MARK: Check Alarm
    //                    group.addTask { [weak self] in
    //                        if room.state != .active { return }
    //                        guard let self else { return }
    //                        let isRunningAlarm = await api.getRunningAlarm(IP: room.ip)
    //                        if room.alarmRunning != isRunningAlarm {
    //                            room.alarmRunning = isRunningAlarm
    //                        }
    //                    }
    //                }
    //            }
    //        }
    //    }
    //
    public func updatePlaybackState(for devices: [SonosDevice]) async throws -> [String] {
        // Collect ids through the group's results — appending to a captured var
        // from concurrent child tasks was a data race.
        await withTaskGroup(of: String?.self) { group in
            for device in devices.filter(\.isVisible) {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    switch await self.getPlaybackInfo(ip: device.ip) {
                    case .playing:
                        await self.updateDevice(device, keyPath: \.isPlaying, value: true)
                        return device.id
                    case .paused:
                        await self.updateDevice(device, keyPath: \.isPlaying, value: false)
                        return nil
                    default:
                        return nil
                    }
                }
            }

            var ids: [String] = []
            for await id in group {
                if let id { ids.append(id) }
            }
            return ids
        }
    }
    
    public func firstPlayingDeviceID(from devices: [SonosDevice]) async throws -> String? {
        let visibleDevices = devices.filter(\.isVisible)
        
        return try await withThrowingTaskGroup(of: String?.self) { group in
            for device in visibleDevices {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let playbackInfo = await self.getPlaybackInfo(ip: device.ip)
                    if playbackInfo == .playing {
                        await self.updateDevice(device, keyPath: \.isPlaying, value: true)
                        return device.id
                    } else if playbackInfo == .paused {
                        await self.updateDevice(device, keyPath: \.isPlaying, value: false)
                    }
                    return nil
                }
            }
            
            // Return as soon as one task finds a playing device
            for try await result in group {
                if let id = result {
                    group.cancelAll()
                    return id
                }
            }
            
            return nil // No device was playing
        }
    }
    
    //    @MainActor
    //    func checkTVMode(from sonosGroups: [SonosGroup]) async {
    //        await withDiscardingTaskGroup { group in
    //            for sonosGroup in sonosGroups {
    //                if sonosGroup.coordinatorRoom.state != .active { return }
    //
    //                group.addTask { [weak self] in
    //                    guard let self else { return }
    ////                    guard let index = self.devices.firstIndex(of: sonosGroup) else { return }
    ////
    ////                    if let playbackService = await playbackService(ip: sonosGroup.ip) {
    ////                        lock.withLock { [weak self] in
    ////                            self?.devices[index].playbackService = playbackService
    ////                        }
    ////                    }
    ////
    ////                    // TODO: Move into playback
    ////                    if sonosGroup.playbackService == .tv {
    ////                        let tvSettings = try? await getTVSettings(ip: sonosGroup.ip)
    ////                        lock.withLock { [weak self] in
    ////                            self?.devices[index].tvSettings = tvSettings
    ////                        }
    ////                    } else {
    ////                        devices[index].tvSettings = nil
    ////                    }
    //                }
    //
    //            }
    //        }
    //    }
    
    //    public func updateGroupMuteState(for roomGroups: [SonosDevice]) async {
    //        await withDiscardingTaskGroup { group in
    //            for roomGroup in roomGroups {
    //                group.addTask {  [weak self] in
    //                    guard let self else { return }
    //                    if roomGroup.state == .active, let isMuted = await self.isMuted(for: roomGroup) {
    //                        guard let index = self.devices.firstIndex(of: roomGroup) else { return }
    //                        lock.withLock { [weak self] in
    //                            self?.devices[index].isMuted = isMuted
    //                        }
    //                    }
    //                }
    //            }
    //        }
    //    }
    //
    //    @MainActor
    //    public func wakeSleepingRooms(rooms: [Room]) async {
    //        await withDiscardingTaskGroup { taskGroup in
    //            for room in rooms {
    //                taskGroup.addTask { [weak self] in
    //                    if let macAddress = room.macAddress, room.state == .sleeping {
    //                        self?.sonosSystemDiscoverService.sendWakeOnLANPacket(macAddress: macAddress)
    //                    }
    //                }
    //            }
    //        }
    //    }
    //
    //    @MainActor
    //    func updateGroupsWatch(from roomGroups: [GroupRoom]) async throws {
    //        try await withThrowingDiscardingTaskGroup { group in
    //            for roomGroup in roomGroups {
    //                group.addTask {
    //                    // MARK: Sleeping
    //                    if roomGroup.coordinatorRoom.state != .active { return }
    //
    //                    async let track = self.getTrack(ip: roomGroup.coordinatorRoom.ip)
    //                    async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
    //                    async let groupVolume = self.getGroupVolume(ip: roomGroup.coordinatorRoom.ip)
    //
    //                    switch await playbackInfo {
    //                    case .playing:
    //                        roomGroup.coordinatorRoom.isPlaying = true
    //                    case .paused:
    //                        roomGroup.coordinatorRoom.isPlaying = false
    //                    default:
    //                        break
    //                    }
    //
    //                    if let groupVolumeAwaited = try? await groupVolume, !roomGroup.isEditingVolume {
    //                        roomGroup.groupVolume = groupVolumeAwaited
    //                    }
    //
    //                    guard let awaitedTrack = await track else { return }
    //
    //                    guard let artworkURL = await self.getArtwork(from: awaitedTrack, size: 200) else {
    //                        if roomGroup.coordinatorRoom.track != awaitedTrack {
    //                            roomGroup.coordinatorRoom.track = awaitedTrack
    //                        } else {
    //                            roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
    //                        }
    //                        return
    //                    }
    //
    //                    awaitedTrack.downloadedArtworkURL = roomGroup.coordinatorRoom.track.downloadedArtworkURL
    //
    //                    if artworkURL != awaitedTrack.artworkURL {
    //                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
    //                    }
    //
    //                    if roomGroup.coordinatorRoom.track != awaitedTrack {
    //                        roomGroup.coordinatorRoom.track = awaitedTrack
    //                        roomGroup.coordinatorRoom.track.downloadedArtworkURL = artworkURL
    //                    } else {
    //                        roomGroup.coordinatorRoom.track.playbackPosition = awaitedTrack.playbackPosition
    //                    }
    //                    return
    //                }
    //            }
    //        }
    //    }
    //
    public func getDevices(useCache: Bool) async throws -> [SonosDevice] {
        try await devicesWithIP().0
    }

    public func getSystem(useCache: Bool) async throws -> ([SonosDevice], String?) {
        let (devices, ip) = try await devicesWithIP()
        guard !ip.isEmpty else { return (devices, nil) }
        // Read the household from whichever address actually answered, which is
        // not necessarily the one we started with.
        return (devices, await api.getHouseHoldID(for: ip))
    }

    // MARK: - Speaker address resolution

    /// Fetches the device list, reporting the address that produced it.
    ///
    /// Discovery is only reached when the stored address cannot answer, so the
    /// common path costs nothing extra.
    private func devicesWithIP() async throws -> ([SonosDevice], String) {
        let ip = await resolveIP()
        guard !ip.isEmpty else { return ([], "") }

        let devices = try await api.getDevices(ipAddress: ip)
        if !devices.isEmpty {
            if unreachableIP == ip { unreachableIP = nil }
            return (devices, ip)
        }

        // `api.getDevices` swallows transport errors and reports an empty array,
        // so an unreachable speaker is indistinguishable from a silent one here.
        // Re-discovering once before giving up is what lets Mini recover when the
        // cached speaker takes a new DHCP lease or drops off the network.
        let fresh = await rediscoverIP(after: ip)
        guard !fresh.isEmpty, fresh != ip else { return (devices, ip) }
        return (try await api.getDevices(ipAddress: fresh), fresh)
    }

    /// The address to talk to, discovering one if nothing usable is stored.
    ///
    /// Clic Mini only ever consumed `sonos_ip`, which the main app and the Watch
    /// publish through iCloud. On a Mac where Clic itself has never run, or before
    /// iCloud has synced, that left every request aimed at "" with no route to
    /// recovery even though a full discovery service was already available here.
    private func resolveIP() async -> String {
        let ip = cachedIP
        if !ip.isEmpty { return ip }
        return await discoverAndStoreIP()
    }

    private func rediscoverIP(after failed: String) async -> String {
        unreachableIP = failed
        if let known = resolvedIP, known != failed { return known }
        return await discoverAndStoreIP()
    }

    private func discoverAndStoreIP() async -> String {
        if let inFlight = ipResolutionTask { return await inFlight.value }

        if let lastFailure = lastFailedDiscovery,
           Date().timeIntervalSince(lastFailure) < Self.discoveryRetryInterval {
            return ""
        }

        let task = Task<String, Never> { [weak self] in
            guard let self else { return "" }
            return await self.discoverIP()
        }
        ipResolutionTask = task
        let ip = await task.value
        ipResolutionTask = nil

        guard !ip.isEmpty else {
            lastFailedDiscovery = Date()
            return ip
        }
        lastFailedDiscovery = nil
        resolvedIP = ip
        if unreachableIP == ip { unreachableIP = nil }
        // Deliberately local. The iCloud copy of `sonos_ip` belongs to the main
        // app, which re-points and clears it on purpose; writing it from Mini
        // would resurrect an address the user just disconnected elsewhere.
        UserDefaults.standard.set(ip, forKey: "sonos_ip")
        return ip
    }

    private func discoverIP() async -> String {
        guard let ips = try? await discoveryService.discoverAllDevices(), !ips.isEmpty else { return "" }

        guard let preferred = preferredHouseHold, !preferred.isEmpty else {
            return ips.first ?? ""
        }

        // Honour the household the user picked — landing on a neighbouring Sonos
        // system would silently swap which speakers Mini controls.
        for ip in ips {
            if await api.householdIdentity(for: ip) == preferred { return ip }
        }
        return ips.first ?? ""
    }

    public var preferredHouseHold: String? {
        get { discoveryService.preferredHousehold }
        set { discoveryService.preferredHousehold = newValue }
    }

    public func getHouseID(for ip: String) async -> String? {
        // Identity form: this is stored as `clic.household` and compared, not
        // sent to the WebSocket.
        return await api.householdIdentity(for: ip)
    }

    public func getAllHouseholdsIPs() async -> Set<String> {
        guard let ips = try? await discoveryService.discoverAllDevices() else { return [] }

        var householdMap = [String: String]()
        var savedIPs = Set<String>()

        await withTaskGroup(of: (String, String).self) { taskGroup in
            for ip in ips {
                taskGroup.addTask { [weak self] in
                    guard let self else { return ("", "") }
                    // Identity form so the S1 and S2 halves of one household
                    // dedupe to a single entry instead of listing twice.
                    let householdID = await self.api.householdIdentity(for: ip)
                    return (householdID ?? "", ip)
                }
            }

            for await (householdID, ip) in taskGroup {
                guard !householdID.isEmpty else { continue }
                if householdMap[householdID] == nil {
                    householdMap[householdID] = ip
                    savedIPs.insert(ip)
                }
            }
        }

        return savedIPs
    }

    public func getGroups(with ip: String) async throws -> [SonosGroup] {
        return try await api.getGroups(ipAddress: ip)
    }

    @MainActor
    public func updateDevices(useCache: Bool = true) async throws {
        // Routed through getDevices so this path gets the same discovery fallback
        // rather than firing at a stale address forever.
        let newDevices = try await getDevices(useCache: useCache)
        let newDeviceIDs = newDevices.map({ $0.id })
        let currentDeviceIDs = devices.map({ $0.id })
        
        if !newDevices.isEmpty && Set(newDeviceIDs) != Set(currentDeviceIDs) {
            // Clear rooms arrays from old devices before replacement
            for index in devices.indices {
                devices[index].rooms.removeAll()
            }
            self.devices = newDevices
        }
    }
    //
    //    @MainActor
    //    public func getGroupsFast() async throws -> [GroupRoom] {
    //        let ips = try await sonosSystemDiscoverService.getAllIPs()
    //
    //        return try await withThrowingTaskGroup(of: [GroupRoom].self, returning: [GroupRoom].self) { taskGroup in
    //            for ip in ips {
    //                taskGroup.addTask { [weak self] in
    //                    guard let self else { return [] }
    //                    return try await api.getGroups(ipAddress: ip)
    //                }
    //            }
    //
    //            // Return the first successful result
    //            if let firstGroups = try await taskGroup.next() {
    //                return firstGroups
    //            }
    //
    //            // If no tasks succeeded, return an empty array
    //            return []
    //        }
    //    }
    //
    //    @MainActor
    //    public func findSystem(useCache: Bool) async throws -> System? {
    //        let IP = try await sonosSystemDiscoverService.getFirstIP(useCache: useCache)
    //        let system = try await api.system(for: IP)
    //        return system
    //    }
    //
    //    public func getGroups(with ip: String) async throws -> [GroupRoom] {
    //        let devices = try await api.getGroups(ipAddress: ip)
    //        return devices
    //    }
    //
    //    public func group(rooms: [Room], to coordinatorID: String) async {
    //        // MARK: Only group new rooms
    //        let nonCoordinatorRooms = rooms.filter{ $0.id != coordinatorID }
    //        for room in nonCoordinatorRooms {
    //            await api.group(IP: room.ip, to: coordinatorID)
    //        }
    //    }
    //
    public func group(rooms: [SonosDevice], to coordinatorID: String) async {
        // MARK: Only group new rooms
        let nonCoordinatorRooms = rooms.filter{ $0.id != coordinatorID }
        for room in nonCoordinatorRooms {
            await api.group(IP: room.ip, to: coordinatorID)
        }
    }
    
    // Returns the new group
    public func speedGroup(devices: [SonosDevice]) async -> SonosDevice? {
        // If there's only one room, ungroup it and return as a single group
        if devices.count == 1, let device = devices.first {
            print("Ungroup", device)
            await api.ungroup(IP: device.ip)
            return device
        }
        
        // Get current devices, fallback to fetching them if necessary
        guard let currentGroups = !devices.isEmpty ? sorted : try? await getDevices(useCache: true) else {
            // Offline
            return nil
        }
        
        let coordinatorIDs = devices.map(\.id)
        var filteredGroups = currentGroups.filter { device in
            device.allDevices.map(\.id).contains(where: coordinatorIDs.contains)
        }
        
        // Update the playback state for filtered devices
        for idx in filteredGroups.indices {
            let playback = await getPlaybackInfo(ip: filteredGroups[idx].ip)
            filteredGroups[idx].isPlaying = (playback == .playing)
        }
        
        // Check if exactly one group is playing
        let playingGroups = filteredGroups.filter { $0.isPlaying }
        var sonosDevice: SonosDevice?
        
        if playingGroups.count == 1 {
            // Use the single playing group as the coordinator group
            sonosDevice = playingGroups.first
        } else {
            // Normal logic: Find the first group matching coordinator IDs
            sonosDevice = filteredGroups.first(where: { coordinatorIDs.contains($0.id) })
        }
        
        guard let sonosDevice else {
            // Offline
            return nil
        }
        
        // Group non-coordinator rooms to the coordinator group
        let nonCoordinatorRooms = devices.filter { $0.id != sonosDevice.id }
        for room in nonCoordinatorRooms {
            if !sonosDevice.rooms.contains(room) {
                print("Group", room.name)
                await api.group(IP: room.ip, to: sonosDevice.id)
            }
        }
        
        // Ungroup any extra rooms from the coordinator group
        print(sonosDevice.allDevices)
        for room in sonosDevice.rooms {
            if !devices.contains(room) {
                print("Ungroup", room.name)
                await api.ungroup(IP: room.ip)
            }
        }
        
        return sonosDevice
    }
    
    public func smartGroup(rooms: [SonosDevice], oldRooms: [SonosDevice], to device: SonosDevice) async -> String? {
        guard let currentIndex = devices.firstIndex(where: { $0.id == device.id }) else { return nil }
        
        var newCoordinatorID: String? = nil
        
        let newRooms = Set(rooms)
        let oldRoomsSet = Set(oldRooms)
        
        // Determine the rooms that have been added
        let addedRooms = newRooms.subtracting(oldRoomsSet)
        
        for room in addedRooms {
            print("Added room: \(room)")
            // MARK: Remove Rooms
            for index in devices.indices {
                devices[index].rooms.removeAll(where: { $0.id == room.id })
            }
            
            if let deviceIndex = devices.firstIndex(where: { $0.id == device.id }) {
                devices[deviceIndex].rooms.append(room)
            }
            
            // MARK: Maybe removall
            await api.group(IP: room.ip, to: device.id)
        }
        
        // Determine the rooms that have been removed
        let removedRooms = oldRoomsSet.subtracting(newRooms)
        for room in removedRooms {
            // Address If Coordinator Room is changing
            if device.id == room.id {
                print("Removing Coordinator")
                if let newCoordinatorRoom = devices[currentIndex].rooms.first {
                    newCoordinatorID = newCoordinatorRoom.id
                }
            }
            
            if let roomIndex = devices.firstIndex(where: { $0.id == room.id }) {
                devices[roomIndex].isHidden = false
                devices[currentIndex].rooms.removeAll { $0.id == room.id }
                await api.ungroup(IP: room.ip)
            }
        }
        
        //        isGroupingTask.cancel()
        //        isGroupingTask = Task {
        //            try? await Task.sleep(for: .seconds(3.5))
        //            if Task.isCancelled { return }
        //            isGrouping = false
        //        }
        
        return newCoordinatorID
    }
    //
    /// Ungroup all rooms
    /// - Parameter group:
    public func ungroup(device: SonosDevice) async {
        await api.ungroup(IP: device.ip)
    }

    public func setDeviceVolume(ip: String, volume: Int) async {
        await api.setVolume(ipAddress: ip, volume: volume)
    }
    
    public func setRelativeVolume(ip: String, volume: Int) async {
        await api.setRelativeVolume(ipAddress: ip, volume: volume)
    }
    
    public func setGroupMute(device: SonosDevice) async {
        var device = device
        device.groupIsMuted.toggle()
        await updateDevice(device, keyPath: \.groupIsMuted, value: device.groupIsMuted)
        await api.setGroupMute(IP: device.ip, mute: device.groupIsMuted)
    }
    
    public func setGroupMute(device: SonosDevice, mute: Bool) async {
        await updateDevice(device, keyPath: \.groupIsMuted, value: mute)
        await api.setGroupMute(IP: device.ip, mute: mute)
    }
    
    public func setDeviceMute(device: SonosDevice, mute: Bool) async {
        await updateDevice(device, keyPath: \.isMuted, value: mute)
        await api.setRoomMute(IP: device.ip, mute: mute)
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
    
    public func snapShotVolume(for devices: [SonosDevice]) {
        let activeDevices = devices.filter { !$0.isHidden }
            .filter { $0.state == .active }
        Task {
            await withDiscardingTaskGroup { taskGroup in
                for device in activeDevices {
                    // No nested unstructured Task — the group must own the work,
                    // otherwise it returns immediately and the floating tasks
                    // hold the service until they finish on their own.
                    taskGroup.addTask { [weak self] in
                        guard let self else { return }
                        await self.snapShotGroup(ip: device.ip)
                    }
                }
            }
        }
    }
    
    
    public func getTrack(ip: String) async -> SonosTrack? {
        await api.getCurrentTrack(ipAddress: ip, prioritizedAlbumArtIP: prioritizedIP())
    }
    //
    //    public func getTrackDetails(ip: String) async -> Track? {
    //        guard let track = await api.getCurrentTrack(ipAddress: ip, prioritizedAlbumArtIP: prioritizedIP()) else { return nil }
    //        guard let (trackMetadata, artworkURL) = await self.getTrackInformation(from: track) else {
    //            return track
    //        }
    //        track.downloadedArtworkURL = artworkURL
    //        track.metadata = trackMetadata
    //        if track.musicService == .tuneIn {
    //            track.artist = trackMetadata?.artist ?? ""
    //        }
    //        return track
    //    }
    //
    //    public func getArtwork(from track: Track, size: Int = 500) async -> URL? {
    //        switch track.musicService  {
    //        case .apple:
    //            guard let artworkString = await musicSearch.appleLookup(id: track.trackID)?.artworkURL(with: "\(size)"), let url = URL(string: artworkString) else {
    //                return nil
    //            }
    //            return url
    //        case .spotify:
    //            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return nil }
    //            if size == 100, let image = spotifyTrack.album.images.sorted(by: { $0.height ?? 0 < $1.height ?? 0 } ).first {
    //                guard let url = URL(string: image.url) else { return nil }
    //                return url
    //            }
    //
    //            if size == 200, spotifyTrack.album.images.count > 2 {
    //                let image = spotifyTrack.album.images[1]
    //                guard let url = URL(string: image.url) else { return nil }
    //                return url
    //            }
    //
    //            guard let artworkString = spotifyTrack.album.images.first?.url, let url = URL(string: artworkString) else { return nil }
    //            return url
    //        case .tidal:
    //            // TODO: Add back when production is enabled for Tidal
    //            return nil
    ////            guard let tidalTrack = await musicSearch.lookupTidalTrack(with: track.trackID) else { return nil }
    ////            return tidalTrack.artwork
    //        case .plex:
    //            guard let id = track.trackID.removingPercentEncoding?.components(separatedBy: ":").last, let plexSong = await musicSearch.lookupPlexSong(with: id) else {
    //                return nil
    //            }
    //            return plexSong.artwork
    //        case .tuneIn:
    //            return nil
    //        case .airplay, .unknown, .library:
    //            return nil
    //        }
    //    }
    //
    //    // TODO: Change size to enum
    //    public func getTrackInformation(from track: Track, size: Int = 500) async -> (Track.Metadata?, URL?)? {
    //        switch track.musicService {
    //        case .spotify:
    //            var imageURL: URL?
    //            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: track.trackID) else { return (nil, nil) }
    //
    //            if size == 100, let image = spotifyTrack.album.images.sorted(by: { $0.height ?? 0 < $1.height ?? 0 } ).first {
    //                imageURL = URL(string: image.url)
    //            } else if size == 200, spotifyTrack.album.images.count > 2 {
    //                let image = spotifyTrack.album.images[1]
    //                imageURL = URL(string: image.url)
    //            } else if let artworkString = spotifyTrack.album.images.first?.url {
    //                imageURL = URL(string: artworkString)
    //            }
    //
    //            return (Track.Metadata(ISRC: spotifyTrack.externalIds.isrc, openInURL: URL(string: spotifyTrack.externalUrls.spotify), contentType: .track), imageURL)
    //        case .apple:
    //            var imageURL: URL? = nil
    //            if track.toPlayable.content.type == .libraryTrack {
    //                // TODO: Do 2 Searches, need to see if it's a catalog item.
    //                guard let appleTrack = await musicSearch.appleLibraryLookup(id: track.trackID) else {
    //                    return (nil, nil)
    //                }
    //                imageURL = appleTrack.data.first?.attributes.artwork?.urlWithSize(width: 500, height: 500)
    //                return (Track.Metadata(ISRC: nil, openInURL: appleTrack.data.first?.songURL, contentType: .libraryTrack), imageURL)
    //            }
    //            guard let appleTrack = await musicSearch.appleLookup(id: track.trackID) else { return (nil, nil) }
    //            imageURL = URL(string: appleTrack.artworkURL(with: "\(size)"))
    //            return (Track.Metadata(ISRC: nil, openInURL: URL(string: appleTrack.trackViewURL), contentType: .track), imageURL)
    //        case .tidal:
    //            guard let tidalTrack = await musicSearch.lookupTidalTrack(with: track.trackID) else { return (nil, nil) }
    //            return (Track.Metadata(ISRC: tidalTrack.metadata?.isrc, openInURL: tidalTrack.content.location, contentType: .track), tidalTrack.artwork)
    //        case .tuneIn:
    //            guard let stationID = track.metadata?.stationID, let tuneInTrack = await musicSearch.lookupTuneInStation(id: stationID) else { return (nil, nil) }
    //            var imageURL = tuneInTrack.imageURL
    //
    //            if let song = tuneInTrack.stationInfo?.song, let artist = tuneInTrack.stationInfo?.artist {
    //                let artworkURL = await musicSearch.searchSpotifySong(song: song, artist: artist)?.tracks?.items.first
    //                imageURL = artworkURL?.album.images.biggestImageURL
    //            }
    //
    //            return (
    //                Track.Metadata(
    //                    ISRC: nil,
    //                    openInURL: tuneInTrack.stationInfo?.location,
    //                    contentType: .radio,
    //                    stationName: tuneInTrack.stationInfo?.name,
    //                    song: tuneInTrack.stationInfo?.song ?? tuneInTrack.stationInfo?.name,
    //                    album: tuneInTrack.stationInfo?.album,
    //                    artist: tuneInTrack.stationInfo?.artist
    //                ),
    //                imageURL
    //            )
    //        case .plex:
    //            guard let id = track.trackID.removingPercentEncoding?.components(separatedBy: ":").last,
    //                  let plexSong = await musicSearch.lookupPlexSong(with: id) else {
    //                return (nil, nil)
    //            }
    //            return (
    //                Track.Metadata(
    //                    ISRC: nil,
    //                    openInURL: nil,
    //                    contentType: .track,
    //                    song: nil,
    //                    album: plexSong.metadata?.album,
    //                    artist: plexSong.metadata?.artist
    //                ),
    //                plexSong.artwork
    //            )
    //        case .unknown:
    //            if track.metadata?.contentType != .track { return (nil, nil) }
    //            guard let artworkURL = await musicSearch.searchSpotifySong(song: track.name, artist: track.artist)?.tracks?.items.first else {
    //                return (nil, nil)
    //            }
    //
    //            return (Track.Metadata(ISRC: nil, openInURL: nil, contentType: .track), artworkURL.album.images.biggestImageURL)
    //        default:
    //            return (nil, nil)
    //        }
    //    }
    //
    //    public func getArtwork(from content: PlayableContent, size: Int = 500) async -> URL? {
    //        switch (content.content.type, content.content.service) {
    //        case (.album, .spotify):
    //            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id) else { return nil }
    //            if size == 100 {
    //                return album.images.thumbnail
    //            } else if size > 100, album.images.count > 2 {
    //                let image = album.images[1]
    //                return URL(string: image.url)
    //            } else if size == 200 {
    //                return album.images.thumbnail
    //            }
    //            return album.images.biggestImageURL
    //        case (.track, .spotify):
    //            var imageURL: URL?
    //            guard let spotifyTrack = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
    //
    //            if size == 100 {
    //                return spotifyTrack.album.images.thumbnail
    //            } else if size > 100, spotifyTrack.album.images.count > 2 {
    //                let image = spotifyTrack.album.images[1]
    //                imageURL = URL(string: image.url)
    //            } else if let artworkString = spotifyTrack.album.images.first?.url {
    //                imageURL = URL(string: artworkString)
    //            }
    //
    //            return imageURL
    //        case (.playlist, .spotify):
    //            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
    //            return playlist.images?.biggestImageURL
    //        case (.track, .apple):
    //            guard let track = await musicSearch.appleLookup(id: content.id) else { return nil }
    //            return URL(string: track.artworkURL)
    //        case (.libraryTrack, .apple):
    //            guard let track = await musicSearch.appleLibraryLookup(id: content.id) else {
    //                return nil
    //            }
    //            return track.data.first?.attributes.artwork?.urlWithSize(width: size, height: size)
    //        case (.album, .apple):
    //            guard let album: Album = try? await musicSearch.lookup(id: content.id) else { return nil }
    //            return album.artwork?.url(width: size, height: size)
    //        case (.playlist, .apple):
    //            guard let playlist: Playlist = try? await musicSearch.lookup(id: content.id) else { return nil }
    //            return playlist.artwork?.url(width: size, height: size)
    //        case (.libraryArtist, .apple):
    //            return await musicSearch.appleLibraryArtistArtwork(name: content.title)
    //        case (.artist, .library):
    //            return await musicSearch.appleLibraryArtistArtwork(name: content.title)
    //        case (.track, .plex):
    //            guard let id = content.id.removingPercentEncoding?.components(separatedBy: ":").last else { return nil }
    //            return await musicSearch.lookupPlexSong(with: id)?.artwork
    //        default:
    //            print(content)
    //            return nil
    //        }
    //    }
    //
    //    public func getContent(from url: URL) async -> PlayableContent? {
    //        guard let content = api.parse(url: url) else { return nil }
    //        switch (content.type, content.service) {
    //        case (.album, .spotify):
    //            guard let album = await musicSearch.spotifyAlbumLookup(id: content.id) else { return nil }
    //            return PlayableContent(title: album.name, subtitle: album.artists.first?.name ?? "", thumbnail: album.images.thumbnail, artwork: album.images.biggestImageURL, content: content)
    //        case (.track, .spotify):
    //            guard let track = await musicSearch.spotifyTrackLookup(id: content.id) else { return nil }
    //            return PlayableContent(title: track.name, subtitle: track.artists.first?.name ?? "", thumbnail: track.album.images.thumbnail, artwork: track.album.images.biggestImageURL, content: content)
    //        case (.playlist, .spotify):
    //            guard let playlist = await musicSearch.spotifyPlaylistLookup(id: content.id) else { return nil }
    //            return PlayableContent(title: playlist.name, subtitle: playlist.owner.displayName, thumbnail: playlist.images?.thumbnail, artwork: playlist.images?.biggestImageURL, content: content)
    //        case (.track, .apple):
    //            guard let song: Song = try? await musicSearch.lookup(id: content.id) else { return nil }
    //            return PlayableContent(title: song.title, subtitle: song.artistName, thumbnail: song.artwork?.url(width: 100, height: 100), artwork: song.artwork?.url(width: 500, height: 500), content: content)
    //        case (.album, .apple):
    //            guard let album: Album = try? await musicSearch.lookup(id: content.id) else { return nil }
    //            return PlayableContent(title: album.title, subtitle: album.artistName, thumbnail: album.artwork?.url(width: 100, height: 100), artwork: album.artwork?.url(width: 500, height: 500), content: content)
    //        case (.playlist, .apple):
    //            guard let playlist: Playlist = try? await musicSearch.lookup(id: content.id) else { return nil }
    //            return PlayableContent(title:   playlist.name, subtitle: playlist.curatorName ?? "", thumbnail: playlist.artwork?.url(width: 100, height: 100), artwork: playlist.artwork?.url(width: 500, height: 500), content: content)
    //        case (.track, .tidal):
    //            guard let playableContent = await musicSearch.lookupTidalTrack(with: content.id) else { return nil }
    //            return playableContent
    //        case (.album, .tidal):
    //            guard let playableContent = await musicSearch.lookupTidalAlbum(with: content.id) else { return nil }
    //            return playableContent
    //        case (_, .tuneIn):
    //            guard let tuneInStation = await musicSearch.lookupTuneInStation(id: content.id) else { return nil }
    //            return tuneInStation.toPlayable
    ////        case (.playlist, .tidal):
    ////            guard let playlist: Playlist = try? await musicSearch.(with: content.id) else { return nil }
    ////            return PlayableContent(title: playlist.name, subtitle: playlist.curatorName ?? "", artwork: playlist.artwork?.url(width: 500, height: 500), content: content)
    //        case (.track, .plex):
    //            guard let id = content.id.removingPercentEncoding?.components(separatedBy: ":").last,
    //                  let track = await musicSearch.lookupPlexSong(with: id) else { return nil }
    //            return track
    //        case (.album, .plex):
    //            guard let id = content.id.removingPercentEncoding?.components(separatedBy: ":").last,
    //                  let album = await musicSearch.lookupPlexAlbum(id: id) else { return nil }
    //            return album
    //        case (.playlist, .plex):
    //            return nil
    ////            guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
    //////                  let playlist = await musicSearch.lookuple(id: id) else { return nil }
    ////            return album
    //        default:
    //            return nil
    //        }
    //    }
    //
    public func pause(IP: String) async {
        let deviceIndex = devices.firstIndex { device in
            device.ip == IP
        }
        
        if let deviceIndex {
            Task { @MainActor in
                let device = devices[deviceIndex]
                updateDevice(device, keyPath: \.isPlaying, value: false)
            }
        }
        
        await api.pause(ipAddress: IP)
    }
    
    public func play(_ IP: String) async {
        let deviceIndex = devices.firstIndex { device in
            device.ip == IP
        }
        
        if let deviceIndex {
            Task { @MainActor in
                let device = devices[deviceIndex]
                updateDevice(device, keyPath: \.isPlaying, value: true)
            }
        }
        
        await api.play(ipAddress: IP)
    }
    
    public func next(ip: String) async {
        await api.next(ipAddress: ip)
    }
    
    /// If playback is more than 3 seconds into the track, restarts the current track.
    /// Otherwise, goes to the previous track.
    public func previous(ip: String) async {
        let playbackPosition = await api.getPlaybackPosition(ipAddress: ip)
        if playbackPosition >= 3000 {
            await api.seek(time: 0, IP: ip)
        } else {
            await api.previous(ipAddress: ip)
        }
    }
    
    //
    //    public func isMuted(for group: SonosDevice) async -> Bool? {
    //        await api.getGroupMute(IP: group.ip)
    //    }
    //
    //    public func isCrossfaded(for group: GroupRoom) async -> Bool? {
    //        await api.crossfade(IP: group.coordinatorRoom.ip)
    //    }
    //
    //    public func setCrossfade(group: GroupRoom, enabled: Bool) async {
    //        group.isCrossfaded = enabled
    //        await api.setCrossfade(IP: group.coordinatorRoom.ip, enabled: enabled)
    //    }
    //
    
    public func getVolume(ip: String) async throws -> Double? {
        try await api.getVolume(ipAddress: ip)
    }
    
    public func getGroupVolume(ip: String) async throws -> Double? {
        try await api.getGroupVolume(ipAddress: ip)
    }
    
    public func getPlaybackInfo(ip: String) async -> SonosPlaybackStatus {
        await api.isPlaying(ipAddress: ip)
    }
    
    public func getCurrentTransportActions(ip: String) async -> AvailableActions? {
        await api.getCurrentTransportActions(IP: ip)
    }
    //
    //    public func sleepTimer(group: GroupRoom, duration: Duration) async {
    //        group.coordinatorRoom.sleepTimer = Date.now.addingTimeInterval(Double(duration.components.seconds))
    //        await api.setSleepTimer(IP: group.ip, duration: duration)
    //    }
    //
    //    public func getSleepTimer(group: GroupRoom) async {
    //        group.coordinatorRoom.sleepTimer = await api.getSleepTimer(IP: group.ip)
    //    }
    //
    //    public func stopSleepTimer(group: GroupRoom) async {
    //        await api.stopSleepTimer(IP: group.ip)
    //        group.coordinatorRoom.sleepTimer = nil
    //    }
    //
    public func setPlayMode(_ ip: String, mode: PlayMode) async {
        await api.setPlayMode(ip, playMode: mode)
    }
    //
    //    public func playbackService(ip: String) async -> PlaybackService? {
    //        await api.mediaInfo(ipAddress: ip)
    //    }
    //
    //    // MARK: TV
    /// `isArcUltra`: pass `true`/`false` when the device type is already known to skip the probe.
    /// Pass `nil` (default) to auto-detect — tries Arc Ultra first, falls back to standard on failure.
    public func getTVSettings(ip: String, isArcUltra: Bool? = nil) async throws -> SonosTVSettings {
        async let audioInputFormat = api.getAudioInputFormat(IP: ip)
        async let nightMode = api.getNightMode(IP: ip)

        let arcUltra: Bool
        if let known = isArcUltra {
            arcUltra = known
        } else {
            arcUltra = (try? await api.getSpeechEnhanceEnabled(IP: ip)) != nil
        }

        if arcUltra {
            async let speechEnhanceEnabled = api.getSpeechEnhanceEnabled(IP: ip)
            async let dialogLevelValue = api.getDialogLevelValue(IP: ip)
            return try await SonosTVSettings(
                nightMode: nightMode,
                dialogLevel: false,
                speechEnhanceEnabled: speechEnhanceEnabled,
                dialogLevelValue: dialogLevelValue,
                audioInputFormat: audioInputFormat
            )
        } else {
            async let dialogLevel = api.getDialogLevel(IP: ip)
            return try await SonosTVSettings(
                nightMode: nightMode,
                dialogLevel: dialogLevel,
                audioInputFormat: audioInputFormat
            )
        }
    }

    public func setDialogLevel(_ IP: String, enabled: Bool) async throws {
        try await api.setDialogLevel(IP: IP, enabled: enabled)
    }

    public func setArcUltraSpeechLevel(_ ip: String, level: SpeechLevel) async throws {
        if level == .off {
            try await api.setSpeechEnhanceEnabled(IP: ip, enabled: false)
        } else {
            async let enable: Void = api.setSpeechEnhanceEnabled(IP: ip, enabled: true)
            async let setLevel: Void = api.setDialogLevelValue(IP: ip, value: level.rawValue)
            _ = try await (enable, setLevel)
        }
    }

    public func setSpeechEnhanceEnabled(_ IP: String, enabled: Bool) async throws {
        try await api.setSpeechEnhanceEnabled(IP: IP, enabled: enabled)
    }

    public func setDialogLevelValue(_ IP: String, value: Int) async throws {
        try await api.setDialogLevelValue(IP: IP, value: value)
    }
    
    public func setNightMode(_ IP: String, enabled: Bool) async throws {
        try await api.setNightMode(IP: IP, enabled: enabled)
    }
    //
    //    public func tvInput(group: GroupRoom) async {
    //        guard let firstSoundBar = group.rooms.first(where: \.isSoundbar) else { return }
    //        await api.tvInput(IP: firstSoundBar.ip, ID: firstSoundBar.id)
    //    }
    //
    public func togglePlayback(ip: String) async {
        let playback = await api.isPlaying(ipAddress: ip)
        if playback.isPlaying {
            await api.pause(ipAddress: ip)
            guard let index = devices.firstIndex(where: { $0.ip == ip }) else { return }
            await updateDevice(devices[index], keyPath: \.isPlaying, value: false)
            
        } else {
            await api.play(ipAddress: ip)
            guard let index = devices.firstIndex(where: { $0.ip == ip }) else { return }
            await updateDevice(devices[index], keyPath: \.isPlaying, value: true)
        }
    }
    //
    //    // TODO: Create Scene
    //    public func createScene(rooms: [Room]) async {
    //        //        let rooms = rooms.filter { room in
    //        //            selections.contains(room.id)
    //        //        }
    //        //        let sceneRooms = rooms.map { SceneRoom(id: $0.id, ip: $0.ip, name: $0.name, volume: $0.volume) }
    //        //        let newScene = SonosScene(name: sceneName, rooms: sceneRooms)
    //        //        scenes.append(newScene)
    //    }
    //
    public func runScene(_ scene: SonosScene) async throws {
        //        let playlistAction = { [weak self] (group: GroupRoom) in
        //            guard let self else { return }
        //            guard let playableContent = scene.playableContent else { return }
        //            try await queue(playable: playableContent, group: group)
        //            await play(ip: group.ip)
        //        }
        
        // Update household if no groups are available
        if devices.isEmpty {
            try await updateHousehold()
        }
        
        // Refresh discovery once if a scene room is missing — it may just be stale
        if scene.rooms.contains(where: { sceneRoom in !devices.contains { $0.id == sceneRoom.id } }) {
            try? await updateHousehold()
        }

        // Run with whichever scene rooms are reachable; skip unplugged/offline speakers
        let discoveredSceneRooms = scene.rooms.compactMap { sceneRoom -> SceneRoom? in
            guard let existingRoom = devices.first(where: { $0.id == sceneRoom.id }) else { return nil }
            return SceneRoom(
                id: existingRoom.id,
                ip: existingRoom.ip,
                name: existingRoom.name,
                volume: sceneRoom.volume
            )
        }

        guard !discoveredSceneRooms.isEmpty else {
            throw SonosDiscoveryError.sonosSystemNotFound
        }
        
        // Create rooms for grouping.
        // NB: don't name this `devices` — a local of that name shadows the
        // `devices` property used above, and the compiler then reports a
        // circular reference while inferring its type.
        let groupDevices = discoveredSceneRooms.map {
            SonosDevice(
                name: $0.name,
                id: $0.id,
                groupID: $0.id,
                ip: $0.ip,
                isHidden: false,
                channelMap: nil,
                satChannelMap: nil,
                state: .active
            )
        }

        // Create the group
        guard let newGroup = await speedGroup(devices: groupDevices) else {
            throw SonosDiscoveryError.sonosSystemNotFound
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
        
        if let playMode = scene.playMode, playMode != .normal {
            await setPlayMode(newGroup.ip, mode: playMode)
        }

        await snapShotGroup(ip: newGroup.ip)
    }
    //
    //    public func seek(trackNumber: Int, on group: GroupRoom) async {
    //        let queueActive = group.playbackService == .queue
    //        if !queueActive {
    //            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
    //        }
    //        await api.seek(trackNumber: trackNumber, IP: group.coordinatorRoom.ip)
    //        try? await Task.sleep(for: .milliseconds(80))
    //        try? await updateGroups(from: [group])
    //    }
    
    public func seek(to queueIndex: Int, on device: SonosDevice) async {
        let queueActive = device.playbackService == .queue
        if !queueActive {
            await api.setAVTransport(IP: device.ip, ID: device.id)
        }
        await api.seek(to: queueIndex, IP: device.ip)
        try? await Task.sleep(for: .milliseconds(80))
        try? await updateTracks(for: [device])
    }
    //
    //    public func getFavoriteList() async {
    //        guard let ip = prioritizedIP() else { return }
    //        self.favorites = await api.getFavorites(for: ip)
    //    }
    //
    //    public func playFavorite(on group: GroupRoom, favoriteID: String) async {
    //        await api.playFavorite(on: group, favoriteID: favoriteID)
    //        await api.play(ipAddress: group.ip)
    //    }
    //
    //    public func favoriteImageURL(favorite: Favorite) -> URL? {
    //        guard let ip = prioritizedIP() else { return nil }
    //        return api.favoriteArtwork(on: favorite, IP: ip)
    //    }
    //
    //    public func deleteFavorite(on group: GroupRoom?, favoriteID: String) async {
    //        guard let foundGroup = devices.first else { return }
    //        await api.deleteFavorite(IP: group?.ip ?? foundGroup.ip, itemID: favoriteID)
    //    }
    //
    //    public func seek(to time: TimeInterval, on group: GroupRoom) async {
    //        await api.seek(to: time, IP: group.coordinatorRoom.ip)
    //    }
    //
    //    public func queueSpotifyArtistTopTracks(id: String, group: GroupRoom) async {
    //        if group.playbackService != .queue {
    //            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
    //        }
    //        await api.queueSpotifyArtistTopTracks(ID: id, IP: group.ip)
    //    }
    //
    //    private func queuePlayable(playable: PlayableContent, group: GroupRoom, position: QueuePosition = .now, index: Int? = nil) async throws {
    //        if [.favorite, .radio].contains(playable.content.type) {
    //            try await api.setAVTransportContent(playableContent: playable, IP: group.ip)
    //            return
    //        }
    //
    //        if playable.content.type.isRadio {
    //            try await startRadio(content: playable, group: group)
    //            return
    //        }
    //
    //        if group.playbackService == .unknown {
    //            group.playbackService = await playbackService(ip: group.ip) ?? .unknown
    //        }
    //
    //        let queueActive = group.playbackService == .queue
    //
    //        if position == .replace {
    //            await api.removeAllTrackFromQueue(IP: group.ip)
    //        }
    //
    //        if !queueActive {
    //            try await api.queuePlayable(playableContent: playable, IP: group.ip, position: .front)
    //            if let index, index > 0 {
    //                let current = await api.getCurrentQueueIndex(ipAddress: group.ip)
    //                await seek(trackNumber: current + index, on: group)
    //                return
    //            }
    //            await api.setAVTransport(IP: group.ip, ID: group.coordinatorID)
    //            return
    //        }
    //
    //        let count = await api.getQueueCount(IP: group.ip)
    //        try await api.queuePlayable(playableContent: playable, IP: group.ip, position: position)
    //
    //        if let index, index > 0 {
    //            let current = await api.getCurrentQueueIndex(ipAddress: group.ip)
    //            await seek(trackNumber: current + index, on: group)
    //            return
    //        }
    //
    //        if position == .now, queueActive, playable.content.type != .playlist, let count, count > 0 {
    //            await next(ip: group.ip)
    //        }
    //    }
    //
    public func getQueueTotal(group: SonosDevice) async throws -> Int? {
        let count = await api.getQueueCount(IP: group.ip)
        return count
    }

    /// Refresh `queueTotal` for every visible coordinator in parallel.
    /// Call this from the menu-bar popover's `onAppear` so re-orders or trims that
    /// happened while the popover was closed (no metadata event fires for those)
    /// are reflected before the user hovers the queue indicator.
    public func refreshQueueTotals() async {
        let targets = devices.filter { $0.isVisible && $0.state == .active }
        await withTaskGroup(of: Void.self) { group in
            for device in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    guard let total = try? await self.getQueueTotal(group: device), total > 0 else { return }
                    await self.updateDevice(device, keyPath: \.queueTotal, value: total)
                }
            }
        }
    }
    //
    //    public func replaceQueue(playable: PlayableContent, group: GroupRoom, index: Int = 0) async throws {
    //        try await api.replaceQueue(playableContent: playable, IP: group.ip, index: index)
    //        await api.play(ipAddress: group.ip)
    //        try? await Task.sleep(for: .milliseconds(120))
    //        try? await updateGroups(from: [group])
    //    }
    //
    //    public func queue(playable: PlayableContent, group: GroupRoom, position: QueuePosition = .now, index: Int? = nil) async throws {
    //        try await queuePlayable(playable: playable, group: group, position: position, index: index)
    //        try? await Task.sleep(for: .milliseconds(120))
    //        try? await updateGroups(from: [group])
    //    }
    //
    //    // TODO: Add queue multiple uris
    //    public func queue(contents: [PlayableContent], group: GroupRoom, position: QueuePosition = .end) async throws {
    //        if position == .replace {
    //            await api.removeAllTrackFromQueue(IP: group.ip)
    //        }
    //        for content in contents {
    //            try await queuePlayable(playable: content, group: group, position: position)
    //        }
    //        if position == .next {
    //            await next(ip: group.ip)
    //        }
    //        try? await Task.sleep(for: .milliseconds(150))
    //        try? await updateGroups(from: [group])
    //    }
    //
    
    public func updateQueue(for device: SonosDevice, total: Int = 0) async {
        async let (service, _) = api.mediaInfo(ipAddress: device.ip)
        async let queue = api.getQueue(IP: device.ip, startingIndex: device.track.position, total: total, priorityIP: prioritizedIP())
        
        // Wait for both async operations to complete
        if let serviceResult = await service {
            await updateDevice(device, keyPath: \.playbackService, value: serviceResult)
        }
        let queueResult = await queue
        await updateDevice(device, keyPath: \.queue, value: queueResult)
    }
    
    public func getQueue(ip: String, with startingIndex: Int, total: Int = 50) async -> [PlayableContent] {
        return await api.getQueue(IP: ip, startingIndex: startingIndex, total: total, priorityIP: prioritizedIP())
    }
    //
    //    public func clearQueue(_ IP: String) async throws {
    //        await api.removeAllTrackFromQueue(IP: IP)
    //    }
    //
    //    public func removeTrackFromQueue(_ IP: String, index: Int) async throws {
    //        await api.removeTrackFromQueue(IP: IP, index: index)
    //    }
    //
    //    public func reorderQueue(_ group: GroupRoom, from: Int, to: Int) async throws {
    //        await api.reorderQueue(group: group, from: from, to: to)
    //    }
    //
    //    public func startRadio(content: PlayableContent, group: GroupRoom) async throws {
    //        try await api.startRadio(playableContent: content, IP: group.ip)
    //        await api.play(ipAddress: group.ip)
    //    }
    //
    //    public func getGroupCoordinatorWithRoom(roomID: String) async -> GroupRoom? {
    //        do {
    //            let devices = try await getGroups(useCache: true)
    //            let group = devices.first { group in
    //                group.rooms.contains { room in
    //                    room.id == roomID
    //                }
    //            }
    //            return group
    //        } catch {
    //            print(error)
    //            return nil
    //        }
    //    }
    //
    //    public func getHouseID() async -> String? {
    //        guard let ip = prioritizedIP() else { return nil }
    //        return await api.getHouseHoldID(for: ip)
    //    }
    //
    //    public func getHouseID(for ip: String) async -> String? {
    //        return await api.getHouseHoldID(for: ip)
    //    }
    //
    //    public func getAllHouseholdsIPs() async -> Set<String> {
    //        guard let ips = try? await sonosSystemDiscoverService.getAllIPs() else { return [] }
    //
    //        var householdMap = [String: String]()
    //        var savedIPs = Set<String>()
    //
    //        await withTaskGroup(of: (String, String).self) { taskGroup in
    //            for ip in ips {
    //                taskGroup.addTask { [weak self] in
    //                    guard let self else { return ("", "") }
    //                    let householdID = await self.api.getHouseHoldID(for: ip)
    //                    return (householdID, ip)
    //                }
    //            }
    //
    //            for await (householdID, ip) in taskGroup {
    //                if householdMap[householdID] == nil {
    //                    householdMap[householdID] = ip
    //                    savedIPs.insert(ip)
    //                }
    //            }
    //        }
    //
    //        print(householdMap)
    //        return savedIPs
    //    }
    //
    //    public func librarySearch(query: String) async -> [PlayableContent] {
    //        // MARK: Update use faster Sonos Devices if Available
    //        guard let ip = prioritizedIP() else { return [] }
    //
    //        async let tracks = api.librarySearch(IP: ip, query: query, filter: .track)
    //        async let artist = api.librarySearch(IP: ip, query: query, filter: .artist)
    //        async let albums = api.librarySearch(IP: ip, query: query, filter: .album)
    //        async let playlist = api.librarySearch(IP: ip, query: query, filter: .playlist)
    //        // TODO: Prioritize by query
    //        let playableContent = await tracks + artist + albums + playlist
    //        return playableContent
    //    }
    //
    //    public func libraryLookup(ID: String) async -> [PlayableContent] {
    //        guard let ip = prioritizedIP() else { return [] }
    //        let playableContent = await api.libraryLookup(IP: ip, id: ID)
    //        return playableContent
    //    }
    //
    //    public func libraryAlbum(name: String) async -> [PlayableContent] {
    //        guard let ip = prioritizedIP() else { return [] }
    //        let playableContent = await api.libraryAlbumLookup(IP: ip, name: name)
    //        return playableContent
    //    }
    //
    //    public func libraryArtist(name: String) async -> [PlayableContent] {
    //        guard let ip = prioritizedIP() else { return [] }
    //        let playableContent = await api.libraryArtistLookup(IP: ip, name: name)
    //        return playableContent
    //    }
    //
    //    public func refreshLibrary() async {
    //        guard let ip = prioritizedIP() else { return  }
    //        await api.refreshLibrary(IP: ip)
    //    }
    //
    //    // MARK: - Sonos Playlists/Queue
    //    public func sonosPlaylists() async -> [PlayableContent] {
    //        // MARK: Update use faster Sonos Devices if Available
    //        guard let ip = prioritizedIP() else { return [] }
    //        return await api.sonosPlaylists(IP: ip)
    //    }
    //
    //    public func sonosPlaylistsTracks(for id: String) async -> [PlayableContent] {
    //        guard let ip = prioritizedIP() else { return [] }
    //        return await api.sonosPlaylistsTracks(IP: ip, id: id)
    //    }
    //
    //    public func createPlaylist(title: String) async {
    //        // MARK: Update use faster Sonos Devices if Available
    //        guard let ip = prioritizedIP() else { return }
    //        return await api.createPlaylist(IP: ip, title: title)
    //    }
    //
    //    public func delete(playlistID: String) async {
    //        // MARK: Update use faster Sonos Devices if Available
    //        guard let ip = prioritizedIP() else { return }
    //        return await api.removePlaylist(IP: ip, itemID: playlistID)
    //    }
    //
    //    public func addToPlaylist(playlistID: String, playableContent: PlayableContent) async {
    //        // MARK: Update use faster Sonos Devices if Available
    //        guard let ip = prioritizedIP() else { return }
    //        return await api.addToPlaylist(IP: ip, playlistID: playlistID, content: playableContent)
    //    }
    //
    //    public func reorderPlaylist(playlistID: String, from: Int, to: Int) async throws {
    //        guard let ip = prioritizedIP() else { return }
    //        await api.reorderSavedQueue(IP: ip, from: from, to: to, savedQueueID: playlistID)
    //    }
    //
    //    public func removeTrackFromPlaylist(playlistID: String, index: Int) async throws {
    //        guard let ip = prioritizedIP() else { return }
    //        await api.removeTrackFromSavedQueue(IP: ip, trackID: String(index), savedQueueID: playlistID)
    //    }
    //
    //    public func saveQueue(ip: String, title: String) async throws {
    //        await api.saveQueue(IP: ip, title: title)
    //    }
    //
    //    public func renamePlaylist(existingPlaylist: PlayableContent, newName: String) async throws {
    //        guard let ip = prioritizedIP() else { return }
    //        await api.renamePlaylist(IP: ip, playlistID: existingPlaylist.id, oldName: existingPlaylist.title, newName: newName)
    //    }
    //
    //    // MARK: - Speaker Settings
    //    public func info(room: Room) async -> DeviceInfo? {
    //        await api.deviceInfo(IP: room.ip)
    //    }
    //
    //    public func getSpeakerSettings(room: Room) async -> SpeakerSettings {
    //        async let bass = api.getBass(ipAddress: room.ip) ?? 0
    //        async let treble = api.getTreble(ipAddress: room.ip) ?? 0
    //        async let loudness = api.getLoudness(ipAddress: room.ip) ?? false
    //        async let isTrueplayEnabled = api.getTrueplayEnabled(ipAddress: room.ip) ?? false
    //
    //        return SpeakerSettings(
    //            isSet: true,
    //            bass: await Double(bass),
    //            treble: await Double(treble),
    //            loudness: await loudness,
    //            truePlay: await isTrueplayEnabled
    //        )
    //    }
    //
    //    public func setBass(room: Room) async {
    //        await api.setBass(ipAddress: room.ip, bass: Int(room.settings.bass))
    //    }
    //
    //    public func setTreble(room: Room) async {
    //        await api.setTreble(ipAddress: room.ip, treble: Int(room.settings.treble))
    //    }
    //
    //    public func setLoudness(room: Room) async {
    //        await api.setLoudness(ipAddress: room.ip, enabled: room.settings.loudness)
    //    }
    //
    //    public func getEQ(room: Room, eq: EQType) async -> Double {
    //        await api.getEQValue(IP: room.ip, eq: eq) ?? 0.0
    //    }
    //
    //    public func setEQ(room: Room, eq: EQType, value: Int) async {
    //        await api.setEQValue(IP: room.ip, eq: eq, value: value)
    //    }
    //
    //    public func resetEQ(room: Room) async {
    //        await api.resetEQ(ipAddress: room.ip)
    //    }
    //
    //    // MARK: Theater Settings
    //    public func getTheaterSettings(room: Room) async -> TheaterSettings {
    //        async let audioInputFormat = api.getAudioInputFormat(IP: room.ip)
    //        async let dialogLevel = api.getDialogLevel(IP: room.ip)
    //        async let nightMode = api.getNightMode(IP: room.ip)
    //        async let subGain = api.getEQValue(IP: room.ip, eq: .subGain)
    //        async let isSubEnabled = api.getEQValue(IP: room.ip, eq: .subEnable)
    //        async let surroundMode = api.getEQValue(IP: room.ip, eq: .surroundMode)
    //        async let musicSurroundLevel = api.getEQValue(IP: room.ip, eq: .musicSurroundLevel)
    //        async let surroundLevel = api.getEQValue(IP: room.ip, eq: .surroundLevel)
    //        async let surroundEnabled = api.getEQValue(IP: room.ip, eq: .surroundEnable)
    //        async let heightLevel = api.getEQValue(IP: room.ip, eq: .heightChannelLevel)
    //
    //        return TheaterSettings(
    //            isSet: true,
    //            nightMode: (try? await nightMode) ?? false,
    //            dialogLevel: (try? await dialogLevel) ?? false,
    //            audioInputFormat: (try? await audioInputFormat) ?? .unknown,
    //            surroundLevel: await surroundLevel ?? 0.0,
    //            musicSurroundLevel: await musicSurroundLevel ?? 0.0,
    //            isSurroundEnable: await (surroundEnabled ?? 0) == 1 ? true : false,
    //            surroundMode:  await surroundMode ?? 0.0,
    //            heightChannel: await heightLevel ?? 0.0,
    //            subGain: await subGain ?? 0.0,
    //            isSubEnabled: await (isSubEnabled ?? 0) == 1 ? true : false
    //        )
    //    }
    //
    //    // MARK: - Alarms
    //    public func listAlarms() async -> [Alarm] {
    //        guard let ip = prioritizedIP() else { return [] }
    //        return await api.listAlarms(IP: ip).sorted(by: { $0.startTime.compare($1.startTime) == .orderedAscending })
    //    }
    //
    //    public func editAlarm(alarm: Alarm, content: PlayableContent?) async  {
    //        guard let ip = prioritizedIP() else { return }
    //        return await api.editAlarm(IP: ip, alarm: alarm, content: content)
    //    }
    //
    //    public func createAlarm(alarm: Alarm, content: PlayableContent?) async  {
    //        guard let ip = prioritizedIP() else { return }
    //        return await api.createAlarm(IP: ip, alarm: alarm, content: content)
    //    }
    //
    //    public func deleteAlarm(alarm: Alarm) async  {
    //        guard let ip = prioritizedIP() else { return }
    //        return await api.deleteAlarm(IP: ip, alarm: alarm)
    //    }
    //
    //    public func parseAlarmClockInfo(uri: String, metadataXML: String?) -> PlayableContent? {
    //        XMLParserSonos().parseAlarmClockInfo(uri: uri, metadataXML: metadataXML)
    //    }
    //
    
    func prioritizedIP() -> String? {
        guard let room = devices.first(where: { $0.ethernetEnabled }) else {
            let filteredRooms = devices.filter { room in
                guard let modelName = room.info?.modelDisplayName.lowercased() else { return false }
                let notTheseModels = ["roam", "move", "play"]
                return notTheseModels.filter { modelName.contains($0)}.count == 0
            }

            if filteredRooms.isEmpty {
                return devices.first?.ip
            }

            return filteredRooms.first?.ip
        }
        return room.ip
    }

    /// One-shot, run on first launch only: if persisted topology matches current devices,
    /// seed each device's track from the cache so the row paints immediately
    /// instead of waiting for the first network pulse to populate.
    @MainActor
    func applyDevicesCacheIfMatching() {
        guard !hasAppliedDevicesCache else { return }
        hasAppliedDevicesCache = true
        guard !devices.isEmpty, let cache = DevicesCacheStore.read() else { return }

        let liveSig = Set(devices.map { "\($0.id):\($0.rooms.map(\.id).sorted().joined(separator: ","))" })
        guard liveSig == cache.topologySignature else { return }

        for cached in cache.devices {
            guard let index = devices.firstIndex(where: { $0.id == cached.deviceID }),
                  devices[index].track.name.isEmpty else { continue }

            var track = SonosTrack(
                trackID: cached.trackID,
                trackURI: cached.trackURI,
                name: cached.trackName,
                artist: cached.trackArtist,
                album: cached.trackAlbum,
                musicService: cached.trackMusicService,
                duration: .seconds(cached.trackDurationSeconds),
                sonosAlbumArtURL: cached.trackSonosAlbumArtURL
            )
            track.downloadedArtworkURL = cached.trackArtworkURL
            devices[index].track = track
        }
    }

    /// Persist current devices + per-device track snapshot to disk.
    @MainActor
    func saveDevicesCache() {
        let snapshots = devices.map { device in
            CachedDevice(
                deviceID: device.id,
                memberRoomIDs: device.rooms.map(\.id).sorted(),
                trackID: device.track.trackID,
                trackURI: device.track.trackURI,
                trackName: device.track.name,
                trackArtist: device.track.artist,
                trackAlbum: device.track.album,
                trackArtworkURL: device.track.downloadedArtworkURL,
                trackSonosAlbumArtURL: device.track.sonosAlbumArtURL,
                trackMusicService: device.track.musicService,
                trackDurationSeconds: Double(device.track.duration.components.seconds)
            )
        }
        DevicesCacheStore.write(DevicesCache(devices: snapshots))
    }
}



