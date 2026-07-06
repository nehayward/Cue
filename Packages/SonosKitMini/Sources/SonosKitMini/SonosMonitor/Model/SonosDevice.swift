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
    public let groupID: String
    public let ip: String
    public var isHidden: Bool
    public var isVisible: Bool { !isHidden }
    public var quality: SonosTrackQuality?
    public var tvAudio: String = ""
    
    /// Playback offset within the currently playing track, in milliseconds.
    /// (Not to be confused with `track.position`, which is the 1-based queue index.)
    public var playbackPositionMillis: Int = 0
    public var totalDuration: Int = 0
    public var lastPositionUpdate: Date = Date()

    /// Smooth-clocked playback offset: linearly interpolates from the last server update.
    public var smoothCurrentPosition: Int {
        guard isPlaying else { return playbackPositionMillis }

        let timeSinceUpdate = Date().timeIntervalSince(lastPositionUpdate)
        let interpolatedMs = Int(timeSinceUpdate * 1000)
        return min(playbackPositionMillis + interpolatedMs, totalDuration)
    }
    
    /// Computed property for current time as formatted string
    public var current: String {
        formatDuration(smoothCurrentPosition)
    }
    
    /// Computed property for time left as formatted string
    public var timeLeft: String {
        let remaining = max(0, totalDuration - smoothCurrentPosition)
        return "-" + formatDuration(remaining)
    }
    
    /// Computed property for total duration as formatted string
    public var total: String {
        formatDuration(totalDuration)
    }
    
    /// Computed property for current progress (0.0 to 1.0)
    public var progress: Double {
        guard totalDuration > 0 else { return 0.0 }
        return Double(smoothCurrentPosition) / Double(totalDuration)
    }
    
    /// Helper function to format time using Duration - handles hours automatically
    private func formatDuration(_ milliseconds: Int) -> String {
        let duration = Duration.milliseconds(milliseconds)
        return duration.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }
    
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
    public var allDevices: [SonosDevice] { [self] + rooms }
    
    public var queueTotal: Int = 0
    
    public let channelMap: String?
    public let satChannelMap: String?
    
    public var isPlaying: Bool = false
    
    public var track: SonosTrack = .empty
    
    public var state: RoomState
    public var battery: Battery? = nil
    public var macAddress: String? = nil
    public var location: URL? = nil
    public var wirelessMode: Int = 0
    public var wirelessLeafOnly: Bool = false
    public var behindWifiExtender: Bool = false
    public var wifiEnabled: Bool = false
    public var ethernetEnabled: Bool = false
    public var voiceConfigState: Int = 0
    public var micEnabled: Bool = false
    public var airPlayEnabled: Bool = false
    public var info: DeviceInfo? = nil
    public var sleepTimer: Date? = nil
    public var alarmRunning: Bool = false
    public var subs: [Sub] = []
    public var queue: [PlayableContent] = []
    
    public var isSoundbar: Bool {
        let keywords = ["Ray", "Beam", "Playbar", "Arc", "Amp", "Playbase"]
        if let info {
            return keywords.contains(where: info.modelDisplayName.contains)
        }
        return false
    }

    public var isArcUltra: Bool {
        info?.modelDisplayName.lowercased().contains("arc ultra") ?? false
    }

    public var sonosAlbumARTURL: URL? {
        guard let endpoint = currentTrackMetadata?.albumArtURI?.unescaped else {
            return nil
        }
    
        let albumArtURL: URL?
        if let url = URL(string: endpoint), url.scheme != nil {
            // If it's already a valid URL with a scheme (http/https), use it directly
            albumArtURL = url
        } else {
            // Otherwise, construct the Sonos-specific URL
            albumArtURL = URL(string: "http://\(ip):1400\(endpoint)")
        }
        
        return albumArtURL
    }
}

extension SonosDevice: Hashable {
//    public static func == (lhs: SonosDevice, rhs: SonosDevice) -> Bool {
//        
//    }
//
//    public func hash(into hasher: inout Hasher) {
//        hasher.combine(id)
//        hasher.combine(isTVMode)
//        hasher.combine(TVSettings)
//        hasher.combine(groupVolume)
//    }
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


extension SonosDevice {
//    public static let gym = Self(name: "Gym", id: "RINCON_7828CAC7352E01400", ip: "192.168.4.49", isHidden: false)
    
    
//    public static let garage = Self(id: "RINCON_B8E937525BB001400:931790658",
//                                    coordinatorID: SonosRoom.garage.id,
//                                    rooms: [.garage],
//                                    coordinatorRoom: .garage)
//    
//    public static let theater = Self(id: "RINCON_48A6B80D8FB401400:2447655188",
//                                     coordinatorID: SonosRoom.theater.id,
//                                     rooms: [.theater],
//                                     coordinatorRoom: .theater,
//                                     tvSettings: SonosTVSettings(nightMode: true, dialogLevel: false, audioInputFormat: .unknown))
//    
//    public static let garage_kitchen_display = Self(id: "RINCON_B8E937525BB001400:931790658",
//                                                    coordinatorID: SonosRoom.garage_kitchen_display.id,
//                                                    rooms: [.garage_kitchen_display],
//                                                    coordinatorRoom: .garage_kitchen_display)
//    
//    public static let garagePlusTheater = Self(id: "RINCON_B8E937525BB001400:931790658",
//                                               coordinatorID: SonosRoom.garage.id,
//                                               rooms: [.garage, .theater],
//                                               coordinatorRoom: .garage)
}
