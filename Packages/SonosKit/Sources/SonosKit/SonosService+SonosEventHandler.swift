//
//  SonosMiniService+SonosEventHandler.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 9/25/25.
//
import Foundation

extension SonosService: SonosEventHandler {
    // MARK: - SonosEventHandler Implementation
    public func onVolumeUpdate(playerId: String, event: VolumeEvent) {
        if event.info.type == "groupVolume" {
//            guard let index = devices.firstIndex(where: { $0.id == playerId }) else {
//                return
//            }
//            if let groupVolume = event.volumeState?.volume {
//                updateDevice(devices[index], keyPath: \.groupVolume, value: Double(groupVolume))
//            }
//            
//            if let isMuted = event.volumeState?.muted {
//                updateDevice(devices[index], keyPath: \.groupIsMuted, value: isMuted)
//            }
        }
    }
    
    public func onPlaybackUpdate(playerId: String, event: PlaybackEvent) {
        if event.info.type == "playbackStatus", let playbackState = event.playbackState {
       
//            guard let index = devices.firstIndex(where: { $0.id == playerId }) else {
//                return
//            }
//            //            guard let groupVolume = event.playbackState?.playbackState =
//            //            devices[index].groupVolume = Double(groupVolume)
//            if playbackState.playbackState == "PLAYBACK_STATE_PLAYING" {
//                updateDevice(devices[index], keyPath: \.isPlaying, value: true)
//
//            }
//            if playbackState.playbackState == "PLAYBACK_STATE_PAUSED" {
//                updateDevice(devices[index], keyPath: \.isPlaying, value: false)
//            }
//            
//            updateDevice(devices[index], keyPath: \.currentPosition, value: playbackState.positionMillis)
//            updateDevice(devices[index], keyPath: \.lastPositionUpdate, value: .now)
            //            devices[index].test = Double(playbackState.positionMillis)
            //            players[playerId]?.lastPositionUpdate = Date() // Update timestamp for smooth animation
        }
        
        //        print(playerId, event)
        
        //        if players[playerId] == nil {
        //            players[playerId] = PlayerState(playerId: playerId)
        //        }
        //
        //        if let playbackState = event.playbackState {
        //            players[playerId]?.isPlaying = playbackState.playbackState == "PLAYBACK_STATE_PLAYING"
        //            players[playerId]?.currentPosition = playbackState.positionMillis
        //            players[playerId]?.lastPositionUpdate = Date() // Update timestamp for smooth animation
        //        }
    }
    
    public func onMetadataUpdate(playerId: String, event: TrackEvent) {
        if event.info.type == "metadataStatus", let metadata = event.metadata {
            guard let index = groups.firstIndex(where: { $0.coordinatorID == playerId }) else {
                return
            }
            if let track = event.metadata?.currentItem?.track {
                if let trackID = track.id {
                    Task {
//                        if let duration = track.durationMillis {
//                            updateDevice(devices[index], keyPath: \.totalDuration, value: duration)
//                        }
//                        let device = devices[index]
//                        // Only trigger for playing devices to avoid showing HUD for all grouped devices
//                        if device.isPlaying, device.track.name != track.name {
//                            try? await updateTracks(for: [devices[index]])
//                            await MainActor.run {
//                                onTrackChanged?(device, device.track)
//                            }
//                        } else {
//                            try? await updateTracks(for: [devices[index]])
//                        }
                    }
                }
//                updateDevice(devices[index], keyPath: \.quality, value: track.quality)
                groups[index].audioQuality = track.quality
            }
            
//            if let htInputFormat = event.metadata?.container?.htInputFormat, let description = htInputFormat.streamDescription {
//                updateDevice(devices[index], keyPath: \.tvAudio, value: description)
//            }
        }
        
    }
    
    public func onGroupUpdate(playerId: String, event: GroupEvent) {
//        if let groupsResponse = event.groupsResponse {
////            for group in groupsResponse.groups {
////                print("Group: \(group.name ?? group.id)")
////                print("Coordinator: \(group.coordinatorId)")
////                print("Players: \(group.playerIds.joined(separator: ", "))")
////            }
////            
////            for player in groupsResponse.players {
////                print("Player: \(player.name)")
////                print("WebSocket URL: \(player.websocketUrl)")
////            }
//            Task {
//                let (newDevices, _) = try await getSystem(useCache: true)
//                let newDeviceIDs = newDevices.map({ $0.id })
//                let currentDeviceIDs = devices.map({ $0.id })
//                
//                if !newDevices.isEmpty && Set(newDeviceIDs) != Set(currentDeviceIDs) {
//                    self.devices = newDevices
//                }
//                
//                // MARK: Update Devices Info
//                try await updateWatchDevices(from: devices)
//            }
//        }
    }
    
    //    func onConnectionStatusChanged(isConnected: Bool, connectionCount: Int) {
    //        self.isConnected = isConnected
    //        self.connectionCount = connectionCount
    //    }
    
    public func onError(playerId: String, error: Error) {
        print("Error for player \(playerId): \(error.localizedDescription)")
    }
    
    // MARK: - Public Methods
    //
    //    func addPlayers(_ configs: [SonosPlayerConfig]) async {
    //        await streamingService.addPlayers(configs, events: [.volume, .playback, .metadata])
    //
    ////        // Set initial selection if none exists
    ////        if selectedPlayerId == nil {
    ////            selectedPlayerId = configs.first?.playerId
    ////        }
    //    }
    //
    //    func disconnectAll() async {
    ////        await streamingService?.disconnectAll()
    //    }
    //
    //    func getPlayer(for playerId: String) -> PlayerState? {
    ////        return players[playerId]
    //    }
}


extension GroupRoom {
    func toConfig(with houseHoldID: String?) -> SonosPlayerConfig {
        .init(ipAddress: ip, playerId: id, groupId: coordinatorID, householdId: houseHoldID)
    }
}
