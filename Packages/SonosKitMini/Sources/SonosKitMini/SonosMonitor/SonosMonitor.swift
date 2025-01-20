import SwiftUI
import Network

public final class SonosMonitor: ObservableObject {
    @Published public var devices: [SonosDevice] = []
    @Published public var isConnectedToWiFi = false
    
    public static var shared = SonosMonitor()
    
    let listener: SonosListener
    let subscriber: SonosSubscriberService
    private var pathMonitor: NWPathMonitor?
    
    init(port: UInt16 = 6116) {
        self.subscriber = .init(callbackPort: port)
        self.listener = .init(port: port)
//        setupEventHandlers()
        setupWiFiMonitoring()
    }
    
//    func setupEventHandlers() {
//        listener.eventHandler = { [weak self] event, deviceID in
//            Task { @MainActor in
//                self?.updateEvent(for: deviceID, event: event)
//            }
//        }
//        
//        listener.zoneManagementHandler = { [weak self] event in
//            Task { @MainActor in
//                self?.updateZone(event: event)
//            }
//        }
//    }
    
    private func setupWiFiMonitoring() {
        pathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnectedToWiFi = path.status == .satisfied
            }
        }
        pathMonitor?.start(queue: DispatchQueue.global())
    }
    
    deinit {
        pathMonitor?.cancel()
    }
    
    public func startListening() async {
        // Initially subscribe to network discovery or a known coordinator
        // You might want to start with one known device to bootstrap the process
        //        let initialIP = "192.168.4.49" // Example: Start with one known device
        //        subscriber.updateDevices([initialIP])
        //        _ = await subscriber.getGroups()
        
//        self.devices = [
//            SonosDevice(name: "Gym", id: "RINCON_7828CAC7352E01400", ip: "192.168.4.49"),
//            SonosDevice(name: "Theater", id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144"),
//            SonosDevice(name: "Bathroom", id: "RINCON_38420B780CEA01400", ip: "192.168.4.153"),
//            SonosDevice(name: "Move", id: "RINCON_C43875011B7C01400", ip: "192.168.5.8"),
//            SonosDevice(name: "Kitchen", id: "RINCON_C43875EE4CCE01400", ip: "192.168.5.136"),
//            SonosDevice(name: "Living Room", id: "RINCON_949F3E6FBAE401400", ip: "192.168.4.48")
//        ]
//        
//        let initialIPs = ["192.168.4.49", "192.168.4.144", "192.168.4.153", "192.168.5.8", "192.168.5.136", "192.168.4.48"]
//        try? await Task.sleep(for: .seconds(1))
//        subscriber.updateDevices(initialIPs)
    }
    
//    func updateZone(event: SonosZoneEvent) {
//        if case let .addGroup(deviceID, newID) = event {
//            print(deviceID, newID)
//            guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
//            guard let newIndex = devices.firstIndex(where: { $0.id == newID }) else { return }
//            if devices[index].rooms.contains(where: { $0.id == newID }) {
//                return
//            }
//            devices[index].rooms.append(devices[newIndex])
//        }
//        
//        if case let .removeFromGroups(deviceId) = event {
//            for (offset, _) in devices.enumerated() {
//                guard let removalIndex = devices[offset].rooms.firstIndex (where: { $0.id == deviceId }) else { continue}
//                devices[offset].rooms.remove(at: removalIndex)
//            }
//        }
//    }
//    
//    func updateEvent(for deviceId: String, event: SonosServiceEvent) {
//        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
//            // Update based on event type
//            switch event {
//            case .groupRenderingControl(let renderingEvent):
//                if let volume = renderingEvent.groupVolume {
//                    devices[index].groupVolume = Double(volume)
//                }
//                devices[index].groupIsMuted = renderingEvent.groupMute ?? false
//                devices[index].groupVolumeChangeable = renderingEvent.groupVolumeChangeable
//            case .avTransport(let avEvent):
//                if let actions = avEvent.currentTransportActions {
//                    let actions = actions.components(separatedBy: ",")
//                    let availableActions = AvailableActions(actions.compactMap(AvailableActions.init))
//                    devices[index].availableActions = availableActions
//                }
//                
//                devices[index].isAlarmRunning = avEvent.isAlarmRunning
//                devices[index].queueTotal = avEvent.queueTotal
//
//                devices[index].trackID = avEvent.trackID
//                devices[index].musicServiceType = avEvent.musicService
//                
//                devices[index].currentTrackURI = avEvent.currentTrackURI
//                devices[index].transportState = avEvent.transportState ?? ""
//                devices[index].currentTrackMetadata = avEvent.currentTrackMetadata
//                devices[index].currentTrackDuration = avEvent.currentTrackDuration ?? ""
//                devices[index].isCrossfaded = avEvent.currentCrossfadeMode
//
//                devices[index].nextTrackURI = avEvent.nextTrackURI
//                devices[index].nextTrackMetadata = avEvent.nextTrackMetadata
//            case .renderingContrl(let renderingControl):
//                devices[index].volume = renderingControl.masterVolume
//                devices[index].isMuted = renderingControl.masterMute
//                
//                if let nightMode = renderingControl.nightMode,
//                   let dialogLevel = renderingControl.dialogLevel {
//                    devices[index].TVSettings = SonosTVSettings(
//                        nightMode: nightMode,
//                        dialogLevel: dialogLevel == 1,
//                        audioInputFormat: nil
//                    )
//                }
//               
//            case .position(let position):
//                devices[index].currentTime = position.relativeTime
//            case .isPlaying(let isPlaying):
//                devices[index].transportState = isPlaying ? "PLAYING" : "PAUSED_PLAYBACK"
//            case .progress(let date):
//                devices[index].lastUpdate = date
//            case .deviceProperties(let battery):
//                devices[index].battery = battery
//            }
//        }
//    }
}
