//
//  SonosDeviceInfo.swift
//  Listener
//
//  Created by Nick Hayward on 1/9/25.
//

import Foundation

// Device model to hold Sonos device information
public struct SonosDevice: Identifiable {
    public var name: String
    public let id: String  // RINCON ID
    public let ip: String
    public var isHidden: Bool { currentTrackURI.contains("x-rincon") }
    
    // Volume properties
    public var groupVolume: Double = 0
    public var groupIsMuted: Bool = false
    public var groupVolumeChangeable: Bool?
    
    public var isCrossfaded: Bool? = nil
    
    public var playMode: PlayMode = .normal
    
    public var isEditingVolume: Bool = false
    public var isEditingPlayback: Bool = false
    public var playbackService: PlaybackService = .unknown
    public var availableActions: AvailableActions = []
    
    // Room properties
    public var volume: Int = 0
    public var isMuted: Bool?
    public var VolumeChangeable: Bool?
    
    // AVTransport properties
    public var transportState: String = ""
    public var currentTrackURI: String = ""
    public var currentTrackMetadata: SonosTrackMetadata?
    public var currentTime: String = ""
    public var currentTrackDuration: String = ""
    
    // MARK: Alarm
    public var isAlarmRunning: Bool = false
    
    public var musicServiceType: SonosMusicServiceType = .unknown
    var trackID: String?
    
    var nextTrackURI: String?
    var nextTrackMetadata: SonosTrackMetadata? = SonosTrackMetadata(title: "", creator: "", album: "", albumArtURI: nil, streamInfo: nil)
    
    // MARK: TVSettings
    public var isTVMode: Bool { currentTrackURI.contains("x-sonos-htastream") }
    
    public var TVSettings: SonosTVSettings?
    
    var lastUpdate: Date = .now
    
    public var rooms: [SonosDevice] = []
    
    var queueTotal: Int?
    

    public let channelMap: String?
    public let satChannelMap: String?
    
    public var isPlaying: Bool = false
    
    public var track: SonosTrack = .empty
    
    public var state: RoomState
    public var battery: Battery? = nil
    public var macAddress: String? = nil
    public var location: URL? = nil
    public var wirelessMode: Int
    public var wirelessLeafOnly: Bool
    public var behindWifiExtender: Bool
    public var wifiEnabled: Bool
    public var ethernetEnabled: Bool
    public var voiceConfigState: Int
    public var micEnabled: Bool
    public var airPlayEnabled: Bool
    public var invisible: Bool
    public var info: DeviceInfo? = nil
    public var sleepTimer: Date? = nil
    public var alarmRunning: Bool = false
    public var subs: [Sub] = []
    public var queue: Set<PlayableContent> = []
    
    
    public var sonosAlbumARTURL: URL? {
        guard let endpoint = currentTrackMetadata?.albumArtURI?.unescaped else {
            return nil
        }
        print("http://\(ip):1400\(endpoint)")
        guard let url = URL(string: "http://\(ip):1400\(endpoint)") else {
            return nil
        }
        
        return url
    }
}


extension SonosDevice: Hashable {
    public static func == (lhs: SonosDevice, rhs: SonosDevice) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        rhs.rooms.count == lhs.rooms.count &&
        lhs.trackID == rhs.trackID &&
        lhs.currentTrackMetadata == rhs.currentTrackMetadata &&
        lhs.isPlaying == rhs.isPlaying 
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}


extension SonosDevice {
    public var nameWithCount: String {
        switch rooms.count {
        case 0:
            "\(name)"
        case 1:
            "\(name) + \(rooms.map(\.name).joined())"
        default:
            "\(name) + \(rooms.count)"
        }
    }
}
