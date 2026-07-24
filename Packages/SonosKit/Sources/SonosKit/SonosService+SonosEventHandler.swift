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
    
    /// Transport changes (play/pause/skip) arrive here within ~100 ms of the
    /// speaker acting on them — well ahead of the 500 ms SOAP pulse, and the
    /// only source of updates at all once the app is backgrounded and the pulse
    /// is cancelled. Writes the cheap state straight onto the model and lets
    /// `liveItemDidChange` fetch the new track when the item actually changed.
    public func onPlaybackUpdate(playerId: String, event: PlaybackEvent) {
        guard event.info.type == "playbackStatus", let playbackState = event.playbackState else { return }
        guard let group = groups.first(where: { $0.coordinatorID == playerId }) else { return }
        // A local play/pause optimistically writes the model and holds `isEditing`
        // for 400 ms; the device echoes its pre-command state in that window.
        guard !isEditing, !group.isEditingPlayback else { return }

        let isPlaying = playbackState.playbackState == "PLAYBACK_STATE_PLAYING"
        if group.coordinatorRoom.isPlaying != isPlaying {
            group.coordinatorRoom.isPlaying = isPlaying
            for room in group.rooms where room.isPlaying != isPlaying {
                room.isPlaying = isPlaying
            }
        }

        // Only correct real drift: the position ticks continuously and every
        // write invalidates each progress-bar consumer.
        let position = TimeInterval(playbackState.positionMillis)
        if abs(group.coordinatorRoom.playbackPosition - position) > 1000 {
            group.coordinatorRoom.updatePlaybackPosition(position)
        }

        liveItemDidChange(itemID: playbackState.itemId, for: group)
        onLiveUpdate?(group)
    }
    
    public func onMetadataUpdate(playerId: String, event: TrackEvent) {
        if event.info.type == "metadataStatus", event.metadata != nil {
            guard let index = groups.firstIndex(where: { $0.coordinatorID == playerId }) else {
                return
            }
            if let track = event.metadata?.currentItem?.track {
                groups[index].audioQuality = track.quality
                groups[index].coordinatorRoom.container = event.metadata?.container
                // The socket carries the *new* song before the poll notices.
                // Prefer the catalog object id; fall back to the name for
                // sources that don't carry one (radio track announcements).
                liveItemDidChange(
                    itemID: track.id?.objectId ?? track.name ?? "",
                    for: groups[index]
                )
            } else {
                groups[index].coordinatorRoom.container = nil
            }
        }
    }

    /// Fetches the full track for `group` when the speaker moves to a different
    /// item, and nothing otherwise.
    ///
    /// Both socket streams report the current item, so this is the single
    /// change-detector for the pair: whichever event lands first wins, and the
    /// other one no-ops. The fetch is deliberately one targeted
    /// `updateTrackInformation` (~1 request per song) rather than a poll —
    /// that's the whole point of holding the socket open.
    @MainActor
    func liveItemDidChange(itemID: String, for group: GroupRoom) {
        guard !itemID.isEmpty else { return }
        guard lastLiveItemIDs[group.coordinatorID] != itemID else { return }
        lastLiveItemIDs[group.coordinatorID] = itemID

        liveTrackRefreshTasks[group.coordinatorID]?.cancel()
        liveTrackRefreshTasks[group.coordinatorID] = Task { @MainActor [weak self] in
            // The socket announces the new item a beat before AVTransport serves
            // it — fetching immediately returns the outgoing track.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            try? await self.updateTrackInformation(for: [group])
            guard !Task.isCancelled else { return }
            self.onLiveUpdate?(group)
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
