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
        guard let index = devices.firstIndex(where: { $0.id == playerId }) else { return }

        if event.info.type == "groupVolume", !devices[index].isEditingVolume {
            if let groupVolume = event.volumeState?.volume {
                updateDevice(devices[index], keyPath: \.groupVolume, value: Double(groupVolume))
            }
            if let isMuted = event.volumeState?.muted {
                updateDevice(devices[index], keyPath: \.groupIsMuted, value: isMuted)
            }
        }

        if event.info.type == "playerVolume", let volumeState = event.volumeState {
            updateSpeakerVolume(id: playerId, volume: volumeState.volume)
            updateSpeakerMute(id: playerId, muted: volumeState.muted)
        }
    }

    public func onPlaybackUpdate(playerId: String, event: PlaybackEvent) {
        guard event.info.type == "playbackStatus", let playbackState = event.playbackState else { return }
        guard let index = devices.firstIndex(where: { $0.id == playerId }) else { return }

        let isPlaying = playbackState.playbackState == "PLAYBACK_STATE_PLAYING"
        updateDevice(devices[index], keyPath: \.isPlaying, value: isPlaying)
        updateDevice(devices[index], keyPath: \.currentPosition, value: playbackState.positionMillis)
        updateDevice(devices[index], keyPath: \.lastPositionUpdate, value: .now)
    }

    public func onMetadataUpdate(playerId: String, event: TrackEvent) {
        guard event.info.type == "metadataStatus", let metadata = event.metadata else { return }
        guard let index = devices.firstIndex(where: { $0.id == playerId }) else { return }

        if let track = metadata.currentItem?.track {
            updateDevice(devices[index], keyPath: \.quality, value: track.quality)

            if track.id != nil {
                let deviceAtIndex = devices[index]
                Task { [weak self] in
                    guard let self else { return }

                    if let duration = track.durationMillis {
                        self.updateDevice(deviceAtIndex, keyPath: \.totalDuration, value: duration)
                    }

                    guard let currentIndex = self.devices.firstIndex(where: { $0.id == playerId }) else { return }
                    let device = self.devices[currentIndex]
                    let trackChanged = device.isPlaying && device.track.name != track.name

                    try? await self.updateTracks(for: [device])

                    if trackChanged {
                        self.onTrackChanged?(device, track.toSonosTrack)
                    }

                    if let queueTotal = try? await self.getQueueTotal(group: device), queueTotal > 0 {
                        self.updateDevice(device, keyPath: \.queueTotal, value: queueTotal)
                    }
                }
            }
        }

        if let htInputFormat = metadata.container?.htInputFormat, let description = htInputFormat.streamDescription {
            updateDevice(devices[index], keyPath: \.tvAudio, value: description)
        }
    }

    public func onGroupUpdate(playerId: String, event: GroupEvent) {
        guard event.groupsResponse != nil else { return }

        Task { [weak self] in
            guard let self else { return }

            let (newDevices, houseHoldID) = try await self.getSystem(useCache: true)
            let newDeviceIDs = Set(newDevices.map(\.id))
            let currentDeviceIDs = Set(self.devices.map(\.id))
            let newGroupIDs = Set(newDevices.map(\.groupID))

            if !newDevices.isEmpty && newDeviceIDs != currentDeviceIDs {
                for index in self.devices.indices {
                    self.devices[index].rooms.removeAll()
                }
                self.devices = newDevices
            }

            try await self.updateWatchDevices(from: self.devices)
            await self.updateRoomVolumes()

            // Reconnect subscriptions when group topology changes
            // Playback/metadata/groupVolume subscriptions are tied to groupId
            if newGroupIDs != self.lastKnownGroupIDs {
                print("[SonosKitMini] Group topology changed, reconnecting subscriptions")
                self.lastKnownGroupIDs = newGroupIDs
                await self.streamingService.disconnectAll()
                let configs = newDevices.map { $0.toConfig(with: houseHoldID) }
                await self.streamingService.addPlayers(configs)
            }
        }
    }

    public func onError(playerId: String, error: Error) {
        print("Error for player \(playerId): \(error.localizedDescription)")
    }
}


extension SonosDevice {
    func toConfig(with houseHoldID: String?) -> SonosPlayerConfig {
        .init(ipAddress: ip, playerId: id, groupId: groupID, householdId: houseHoldID)
    }
}
