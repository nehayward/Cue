import Foundation
import Observation
import SwiftUI
import CloudKit
import os


@Observable
public final class SonosMiniService {
    public static var shared = SonosMiniService()
    public var devices: [SonosDevice] = []
    
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
    
    private let sonosMonitor = SonosMonitor.shared
    
    @ObservationIgnored private lazy var discoveryService = SonosSystemDiscoveryService()
    @ObservationIgnored private lazy var api = SonosAPI()
    @ObservationIgnored private var cachedIP: String {
        NSUbiquitousKeyValueStore.default.string(forKey: "sonos_ip") ?? ""
    }
    
    private func updateDevice<T>(_ device: SonosDevice, keyPath: WritableKeyPath<SonosDevice, T>, value: T) {
        guard let index = self.devices.firstIndex(where: { $0.id == device.id }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.devices[index][keyPath: keyPath] = value
        }
    }
    
    private init() { }
    
    func setupListeners() {
        sonosMonitor.listener.eventHandler = { [weak self] event, deviceID in
            Task { @MainActor in
                self?.updateEvent(for: deviceID, event: event)
            }
        }
        
        sonosMonitor.listener.zoneManagementHandler = { [weak self] event in
            Task { @MainActor in
                self?.updateZone(event: event)
            }
        }
    }
    
    func updateZone(event: SonosZoneEvent) {
        if case let .addGroup(deviceID, newID) = event {
            print(deviceID, newID)
            guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
            guard let newIndex = devices.firstIndex(where: { $0.id == newID }) else { return }
            if devices[index].rooms.contains(where: { $0.id == newID }) {
                return
            }
            devices[index].rooms.append(devices[newIndex])
        }
        
        if case let .removeFromGroups(deviceId) = event {
            for (offset, _) in devices.enumerated() {
                guard let removalIndex = devices[offset].rooms.firstIndex(where: { $0.id == deviceId }) else { continue }
                devices[offset].rooms.remove(at: removalIndex)
            }
        }
        
    }
    
    @MainActor
    func updateEvent(for deviceId: String, event: SonosServiceEvent) {
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        switch event {
        case .groupRenderingControl(let renderingEvent):
            if let volume = renderingEvent.groupVolume, !devices[index].isEditingVolume {
                devices[index].groupVolume = Double(volume)
            }
            devices[index].groupIsMuted = renderingEvent.groupMute ?? false
            devices[index].groupVolumeChangeable = renderingEvent.groupVolumeChangeable
            
        case .avTransport(let avEvent):
            if let actions = avEvent.currentTransportActions {
                let actions = actions.components(separatedBy: ",")
                let availableActions = AvailableActions(actions.compactMap(AvailableActions.init))
                devices[index].availableActions = availableActions
            }
            devices[index].isAlarmRunning = avEvent.isAlarmRunning
            devices[index].queueTotal = avEvent.queueTotal
            
            devices[index].trackID = avEvent.trackID
            devices[index].musicServiceType = avEvent.musicService
            
            devices[index].currentTrackURI = avEvent.currentTrackURI
            devices[index].transportState = avEvent.transportState ?? ""
            devices[index].currentTrackMetadata = avEvent.currentTrackMetadata
            devices[index].currentTrackDuration = avEvent.currentTrackDuration ?? ""
            devices[index].isCrossfaded = avEvent.currentCrossfadeMode
            
            devices[index].nextTrackURI = avEvent.nextTrackURI
            devices[index].nextTrackMetadata = avEvent.nextTrackMetadata
            
        case .renderingContrl(let renderingControl):
            devices[index].volume = renderingControl.masterVolume
            devices[index].isMuted = renderingControl.masterMute
            
            if let nightMode = renderingControl.nightMode,
               let dialogLevel = renderingControl.dialogLevel {
                devices[index].TVSettings = SonosTVSettings(
                    nightMode: nightMode,
                    dialogLevel: dialogLevel == 1,
                    audioInputFormat: nil
                )
            }
            
        case .position(let position):
            devices[index].currentTime = position.relativeTime
            
        case .isPlaying(let isPlaying):
            devices[index].transportState = isPlaying ? "PLAYING" : "PAUSED_PLAYBACK"
            devices[index].isPlaying = isPlaying
            
        case .progress(let date):
            devices[index].lastUpdate = date
            
        case .deviceProperties(let event):
            devices[index].battery = event.battery
            if let name = event.name {
                devices[index].name = name
            }
            //                    devices[index].name = battery
        }
        
    }
    
    //
    //    @ObservationIgnored private lazy var musicSearch = MusicSearchService()
    //    @ObservationIgnored private var isGroupingTask: Task<Void, Error> = Task { }
    //
    //    public var systemState = SonosSystemState()
    //    public var isSearching: Bool { sonosSystemDiscoverService.isSearching }
    //    public var lastKnownIP: String { sonosSystemDiscoverService.sonosStorageIP.sonosIP }
    //    public var state: String { sonosSystemDiscoverService.lastKnownState }
    //    public var preferredHouseHold: String? {
    //        get {
    //            sonosSystemDiscoverService.preferredHouseHold
    //        }
    //        set {
    //            sonosSystemDiscoverService.preferredHouseHold = newValue
    //        }
    //    }
    //
    //    public var parserError: String?
    //
    //    @ObservationIgnored public var monitorTask: Task<Void, Error> = Task { }
    //    @ObservationIgnored public var sonosPulse: Task<Void, Error> = Task { }
    //    @ObservationIgnored public var watcher: Task<Void, Error> = Task { }
    //    @ObservationIgnored public var isEditing: Bool = false
    //    @ObservationIgnored public var isGrouping: Bool = false
    //
    //    public var isRunning: Bool { !sonosPulse.isCancelled }
    //    public var devicesChanged: (([GroupRoom]) -> ()) = { _ in }
    //
    //    public init () {
    //        sonosPulse.cancel()
    //    }
    //
    //    public var system: System?
    
    //    public var primaryHouseID: String? { sonosSystemDiscoverService.houseHoldIDs.first }
    //    public var houseIDs: Set<String> { sonosSystemDiscoverService.houseHoldIDs }
    //
    
    public func snapShotVolume(for devices: [SonosDevice]) {
        let groups = devices.filter { !$0.isHidden }
            .filter { $0.state == .active }
        
        for group in groups {
            Task {
                await snapShotGroup(ip: group.ip)
            }
        }
    }
    
    public func load(useCache: Bool) async throws {
        //        let newGroups = try await getGroups(useCache: useCache)
        let newDevices = try await getDevices(useCache: useCache)
        
        // Change to direct array comparison since order is preserved
        let newDeviceIDs = newDevices.map({ $0.id })
        let currentDeviceIDs = devices.map({ $0.id })
        
        if !newDevices.isEmpty && Set(newDeviceIDs) != Set(currentDeviceIDs) {
            self.devices = newDevices
            print("Refreshed")
            print("NewGroup \(newDevices.count), Old \(devices.count)")
            print(newDeviceIDs)
            print(currentDeviceIDs)
        }
        setupListeners()
        sonosMonitor.subscriber.updateDevices(devices.map{ $0.ip })
        sonosMonitor.subscriber.subscribe()
        
        snapShotVolume(for: devices)
        
        for device in devices {
            guard let index = devices.firstIndex(of: device) else { continue }
            
            // Update coordinator room properties
            //            if keyPaths.contains(\SonosGroup.coordinatorRoom.ethernetEnabled) {
            //                household.devices.update(with: group)
            //            }
            //
            //            if keyPaths.contains(\SonosGroup.coordinatorRoom.micEnabled) {
            //                household.devices[index].coordinatorRoom.micEnabled = newGroup.coordinatorRoom.micEnabled
            //            }
            //            if keyPaths.contains(\SonosGroup.coordinatorRoom.battery) {
            //                household.devices[index].coordinatorRoom.battery = newGroup.coordinatorRoom.battery
            //            }
            //            if keyPaths.contains(\SonosGroup.coordinatorRoom.info),
            //               currentGroup.coordinatorRoom.info == nil,
            //               newGroup.coordinatorRoom.state == .active {
            //                currentGroup.coordinatorRoom.info = await api.deviceInfo(IP: newGroup.coordinatorRoom.ip)
            //            }
            
            //            // Update room properties
            //            for roomIndex in currentGroup.rooms.indices {
            //                let currentRoom = currentGroup.rooms[roomIndex]
            //                let newRoom = newGroup.rooms[roomIndex]
            //
            //                if keyPaths.contains(\Room.info), currentRoom.info == nil, newGroup.coordinatorRoom.state == .active {
            //                    currentRoom.info = await api.deviceInfo(IP: currentRoom.ip)
            //                }
            //                if keyPaths.contains(\Room.settings), !currentRoom.settings.isSet {
            //                    currentRoom.settings = await getSpeakerSettings(room: currentRoom)
            //                }
            //            }
        }
        
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
                    //                    async let groupVolume = getGroupVolume(ip: device.ip)
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
                    //                    if let groupVolumeAwaited = try? await groupVolume, !device.isEditingVolume {
                    //                        lock.withLock { [weak self] in
                    //                            self?.devices[index].groupVolume = groupVolumeAwaited
                    //                        }
                    //                    }
                    
                    
                    
                    if let awaitedActions = await availableActions {
                        updateDevice(device, keyPath: \.availableActions, value: awaitedActions)
                    }
                    
                    guard let awaitedTrack = await track else {
                        return
                    }
                    
                    print(awaitedTrack)
                    
                    if device.track.id != awaitedTrack.id, !device.isEditingPlayback {
                        let newMetadata = SonosTrackMetadata(
                            title: awaitedTrack.name,
                            creator: awaitedTrack.artist,
                            album: awaitedTrack.album,
                            albumArtURI: awaitedTrack.albumArtURI,
                            streamInfo: nil
                        )
                        
                        // Update with the new metadata using updateDevice helper
                        updateDevice(device, keyPath: \.currentTrackMetadata, value: newMetadata)
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
                        updateDevice(device, keyPath: \.currentTrackMetadata, value: newMetadata)
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
    //    @MainActor
    //    public func updateGroupsCheckPlayback() async throws {
    //        let newGroup = try await getGroups(useCache: true)
    //        if !newGroup.isEmpty && newGroup != devices {
    //            self.devices = newGroup
    //            self.rooms = newGroup.flatMap(\.rooms)
    //        }
    //
    //        await withDiscardingTaskGroup { group in
    //            for (_, roomGroup) in devices.enumerated() {
    //                group.addTask {
    //                    async let playbackInfo = self.getPlaybackInfo(ip: roomGroup.coordinatorRoom.ip)
    //                    switch await playbackInfo {
    //                    case .playing:
    //                        roomGroup.coordinatorRoom.isPlaying = true
    //                    case .paused:
    //                        roomGroup.coordinatorRoom.isPlaying = false
    //                    default:
    //                        break
    //                    }
    //                }
    //            }
    //        }
    //    }
    
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
        let devices = try await api.getDevices(ipAddress: cachedIP)
        return devices
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
    //    // Returns the new group
    //    public func speedGroup(rooms: [Room]) async -> GroupRoom? {
    //        // If there's only one room, ungroup it and return as a single group
    //        if rooms.count == 1, let room = rooms.first {
    //            await api.ungroup(IP: room.ip)
    //            return room.toGroup
    //        }
    //
    //        // Get current devices, fallback to fetching them if necessary
    //        guard let currentGroups = !sorted.isEmpty ? sorted : try? await getGroupsFast() else {
    //            // Offline
    //            return nil
    //        }
    //
    //        let coordinatorIDs = rooms.map(\.id)
    //        let filteredGroups = currentGroups.filter { group in
    //            group.rooms.map(\.id).contains(where: coordinatorIDs.contains)
    //        }
    //
    //        // Update the playback state for filtered devices
    //        for idx in filteredGroups.indices {
    //            let playback = await getPlaybackInfo(ip: filteredGroups[idx].ip)
    //            filteredGroups[idx].coordinatorRoom.isPlaying = (playback == .playing)
    //        }
    //
    //        // Check if exactly one group is playing
    //        let playingGroups = filteredGroups.filter { $0.coordinatorRoom.isPlaying }
    //        var coordinatorGroup: GroupRoom?
    //
    //        if playingGroups.count == 1 {
    //            // Use the single playing group as the coordinator group
    //            coordinatorGroup = playingGroups.first
    //        } else {
    //            // Normal logic: Find the first group matching coordinator IDs
    //            coordinatorGroup = filteredGroups.first(where: { coordinatorIDs.contains($0.coordinatorID) })
    //        }
    //
    //        guard let coordinatorGroup else {
    //            // Offline
    //            return nil
    //        }
    //
    //        // Group non-coordinator rooms to the coordinator group
    //        let nonCoordinatorRooms = rooms.filter { $0.id != coordinatorGroup.coordinatorID }
    //        for room in nonCoordinatorRooms {
    //            if !coordinatorGroup.rooms.contains(room) {
    //                await api.group(IP: room.ip, to: coordinatorGroup.coordinatorID)
    //            }
    //        }
    //
    //        // Ungroup any extra rooms from the coordinator group
    //        for room in coordinatorGroup.rooms {
    //            if !rooms.contains(room) {
    //                await api.ungroup(IP: room.ip)
    //            }
    //        }
    //
    //        return coordinatorGroup
    //    }
    //
    //    public func smartGroup(rooms: [Room], oldRooms: [Room], to group: GroupRoom) async -> String? {
    //        var newCoordinatorID: String? = nil
    //
    //        isGrouping = true
    //        let newRooms = Set(rooms)
    //        let oldRoomsSet = Set(oldRooms)
    //
    //        // Determine the rooms that have been added
    //        let addedRooms = newRooms.subtracting(oldRoomsSet)
    //
    //        for room in addedRooms {
    //            print("Added room: \(room)")
    //            // MARK: Remove Rooms
    //            for group in devices {
    //                group.rooms.removeAll(where: { $0.id == room.id })
    //            }
    //
    //            if let groupIndex = devices.firstIndex(where: { groupLooking in groupLooking.coordinatorID == group.coordinatorID }) {
    //                devices[groupIndex].rooms.append(room)
    //            }
    //
    //            devices.removeAll(where: { group in group.coordinatorID == room.id })
    //            await api.group(IP: room.ip, to: group.coordinatorID)
    //        }
    //
    //        // Determine the rooms that have been removed
    //        let removedRooms = oldRoomsSet.subtracting(newRooms)
    //        for room in removedRooms {
    //            print("Removed room: \(room)")
    //            let groupIndex = devices.firstIndex { groupResult in
    //                groupResult.coordinatorID == group.coordinatorID
    //            }
    //
    //            if let groupIndex {
    //                devices[groupIndex].rooms.removeAll { roomResult in
    //                    roomResult.id == room.id
    //                }
    //                print(devices[groupIndex].rooms)
    //
    //                // Address If Coordinator Room is changing
    //                if group.coordinatorID == room.id {
    //                    print("Removing Coordinator")
    //                    if let newCoordinatorRoom = devices[groupIndex].rooms.first {
    //                        devices[groupIndex].coordinatorRoom = newCoordinatorRoom
    //                        newCoordinatorID = newCoordinatorRoom.id
    //                    }
    //                }
    //            }
    //
    //            devices.append(room.toGroup)
    //            await api.ungroup(IP: room.ip)
    //        }
    //
    //        isGroupingTask.cancel()
    //        isGroupingTask = Task {
    //            try? await Task.sleep(for: .seconds(3.5))
    //            if Task.isCancelled { return }
    //            isGrouping = false
    //        }
    //
    //        return newCoordinatorID
    //    }
    //
    //    /// Ungroup all rooms
    //    /// - Parameter group:
    //    public func ungroup(group: GroupRoom) async {
    //        await api.ungroup(IP: group.ip)
    //    }
    //
    //    public func setDeviceVolume(ip: String, volume: Int) async {
    //        await api.setVolume(ipAddress: ip, volume: volume)
    //    }
    //
    //    public func setRelativeVolume(ip: String, volume: Int) async {
    //        await api.setRelativeVolume(ipAddress: ip, volume: volume)
    //    }
    //
    public func setGroupMute(device: SonosDevice) async {
        var device = device
        device.groupIsMuted.toggle()
        updateDevice(device, keyPath: \.groupIsMuted, value: device.groupIsMuted)
        await api.setGroupMute(IP: device.ip, mute: device.groupIsMuted)
    }
    //
    //    @MainActor
    //    public func setRoomMute(room: Room, mute: Bool) async {
    //        room.isMuted = mute
    //        await api.setRoomMute(IP: room.ip, mute: mute)
    //    }
    //
    //    public func setRoomMute(IP: String, mute: Bool) async {
    //        await api.setRoomMute(IP: IP, mute: mute)
    //    }
    //
    public func setGroupVolume(ip: String, volume: Int) async {
        await api.setGroupVolume(IP: ip, volume: volume)
    }
    //
    //    public func setRelativeGroupVolume(ip: String, volume: Int) async {
    //        await api.setRelativeGroupVolume(ipAddress: ip, volume: volume)
    //    }
    //
    public func snapShotGroup(ip: String) async {
        await api.snapshotGroupVolume(ipAddress: ip)
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
    //    public func pause(ip: String) async {
    //        let groupIndex = devices.firstIndex { group in
    //            group.coordinatorRoom.ip == ip
    //        }
    //
    //        if let groupIndex {
    //            for (index, _) in devices[groupIndex].rooms.enumerated() {
    //                Task { @MainActor in
    //                    devices[groupIndex].rooms[index].isPlaying = false
    //                    devices[groupIndex].coordinatorRoom.isPlaying = false
    //                }
    //            }
    //        }
    //
    //        isEditing = true
    //        await api.pause(ipAddress: ip)
    //        try? await Task.sleep(for: .milliseconds(400))
    //        isEditing = false
    //    }
    //
    //    public func play(ip: String) async {
    //        let groupIndex = devices.firstIndex { room in
    //            room.coordinatorRoom.ip == ip
    //        }
    //
    //        if let groupIndex {
    //            Task { @MainActor in
    //                for (index, _) in devices[groupIndex].rooms.enumerated() {
    //                    devices[groupIndex].rooms[index].isPlaying = true
    //                    devices[groupIndex].coordinatorRoom.isPlaying = true
    //                }
    //            }
    //        }
    //        isEditing = true
    //        await api.play(ipAddress: ip)
    //        try? await Task.sleep(for: .milliseconds(400))
    //        isEditing = false
    //    }
    //
    public func next(ip: String) async {
        await api.next(ipAddress: ip)
    }
    //
    //    public func previous(ip: String) async {
    //        // TODO: Seek to beginning of track
    //        await api.previous(ipAddress: ip)
    //    }
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
    //    public func getVolume(ip: String) async throws -> Double {
    //        try await api.getVolume(ipAddress: ip)
    //    }
    //
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
    //    @MainActor
    //    public func playMode(ip: String) async -> PlayMode {
    //        await api.playMode(ip)
    //    }
    //
    //    public func setPlayMode(_ IP: String, mode: PlayMode) async {
    //        await api.setPlayMode(IP, playMode: mode)
    //    }
    //
    //    public func playbackService(ip: String) async -> PlaybackService? {
    //        await api.mediaInfo(ipAddress: ip)
    //    }
    //
    //    // MARK: TV
    //    public func getTVSettings(ip: String) async throws -> SonosTVSettings {
    //        async let audioInputFormat = api.getAudioInputFormat(IP: ip)
    //        async let dialogLevel = api.getDialogLevel(IP: ip)
    //        async let nightMode = api.getNightMode(IP: ip)
    //
    //        return try await SonosTVSettings(
    //            nightMode: nightMode,
    //            dialogLevel: dialogLevel,
    //            audioInputFormat: audioInputFormat
    //        )
    //    }
    
    public func setDialogLevel(_ IP: String, enabled: Bool) async throws {
        try await api.setDialogLevel(IP: IP, enabled: enabled)
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
            updateDevice(devices[index], keyPath: \.isPlaying, value: false)
            
        } else {
            await api.play(ipAddress: ip)
            guard let index = devices.firstIndex(where: { $0.ip == ip }) else { return }
            updateDevice(devices[index], keyPath: \.isPlaying, value: true)
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
    //    public func runScene(_ scene: SonosScene) async throws {
    //        let playlistAction = { [weak self] (group: GroupRoom) in
    //            guard let self else { return }
    //            guard let playableContent = scene.playableContent else { return }
    //            try await queue(playable: playableContent, group: group)
    //            await play(ip: group.ip)
    //        }
    //
    //        let rooms = scene.rooms.map { Room(id: $0.id, ip: $0.ip, name: $0.name)}
    //        let newGroup = await speedGroup(rooms: rooms)
    //        for room in scene.rooms {
    //            await setDeviceVolume(ip: room.ip, volume: Int(room.volume))
    //            await setRoomMute(IP: room.ip, mute: false)
    //        }
    //
    //        guard let newGroup else { return }
    //        await snapShotGroup(ip: newGroup.ip)
    //        try await playlistAction(newGroup)
    //    }
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
    //    public func getQueueTotal(group: GroupRoom) async throws -> Int? {
    //        let count = await api.getQueueCount(IP: group.ip)
    //        return count
    //    }
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
    //    public func getQueue(ip: String) async -> [PlayableContent] {
    //        await api.getQueue(IP: ip, prioritizedAlbumArtIP: prioritizedIP() )
    //    }
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
        let allRooms = devices.flatMap(\.rooms)
        guard let room = allRooms.first(where: { $0.ethernetEnabled }) else {
            let filteredRooms = allRooms.filter { room in
                guard let modelName = room.info?.modelDisplayName.lowercased() else { return false }
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
    
//    private func updateDevice<T>(_ device: SonosDevice, keyPath: WritableKeyPath<SonosDevice, T>, value: T) {
//        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
//        lock.withLock { [weak self] in
//            guard let self else { return }
//            devices[index][keyPath: keyPath] = value
//        }
//    }
}



