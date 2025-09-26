//
//  SonosMiniService+SonosEventHandler.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 9/25/25.
//
import Foundation

extension SonosMiniService: SonosEventHandler {
    // MARK: - SonosEventHandler Implementation
    public func onVolumeUpdate(playerId: String, event: VolumeEvent) {
        if event.info.type == "groupVolume" {
            guard let index = devices.firstIndex(where: { $0.id == playerId }) else {
                return
            }
            guard let groupVolume = event.volumeState?.volume else { return }
            devices[index].groupVolume = Double(groupVolume)
        }
    }
    
    public func onPlaybackUpdate(playerId: String, event: PlaybackEvent) {
        if event.info.type == "playbackStatus", let playbackState = event.playbackState {
            guard let index = devices.firstIndex(where: { $0.id == playerId }) else {
                return
            }
            //            guard let groupVolume = event.playbackState?.playbackState =
            //            devices[index].groupVolume = Double(groupVolume)
            if playbackState.playbackState == "PLAYBACK_STATE_PLAYING" {
                devices[index].isPlaying = true
            }
            if playbackState.playbackState == "PLAYBACK_STATE_PAUSED" {
                devices[index].isPlaying = false
            }
            
            devices[index].currentPosition  = playbackState.positionMillis
            devices[index].lastPositionUpdate = Date()
            
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
        print(playerId, event)
        if event.info.type == "metadataStatus", let metadata = event.metadata {
            guard let index = devices.firstIndex(where: { $0.id == playerId }) else {
                return
            }
            if let track = event.metadata?.currentItem?.track {
                if let trackID = track.id {
                    Task {
//                        guard trackID.objectId != devices[index].trackID else {
//                            if let duration = track.durationMillis {
//                                devices[index].track.duration = .milliseconds(duration)
//                            }
//                            return
//                        }
//                        try? await updateDevices(from: [devices[index]])
                        if let duration = track.durationMillis {
                            devices[index].totalDuration = duration
                        }
                        try? await updateTracks(for: [devices[index]])

                    }
                }
            }
        }
        
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


extension SonosDevice {
    var toConfig: SonosPlayerConfig {
        .init(ipAddress: ip, playerId: id, groupId: groupID)
    }
}
