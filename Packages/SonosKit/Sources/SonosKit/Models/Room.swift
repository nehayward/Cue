import Foundation
import Collections
import Observation
import os

@Observable
public final class Room: Identifiable, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()

    public let id: String
    public let ip: String
    public let name: String
    public let channelMap: String?
    public let satChannelMap: String?
    public var volume: Double = 0
    public var isMuted: Bool = false
    public var isPlaying: Bool = false
    public var track: Track = .empty
    public var isEditingVolume: Bool = false
    public var state: RoomState
    public var battery: Battery?
    public var macAddress: String?
    public var location: URL?
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
    public var queue: OrderedSet<PlayableContent> = []
    public var queueTotal: Int = 0

    // MARK: Settings
    public var settings = SpeakerSettings(isSet: false)
    public var theaterSettings = TheaterSettings(isSet: false)

    public var isSoundbar: Bool {
        let keywords = ["Ray", "Beam", "Playbar", "Arc"]
        if let info {
            return keywords.contains(where: info.modelDisplayName.contains)
        }
        return false
    }

    public init(
        id: String,
        ip: String,
        name: String,
        channelMap: String? = nil,
        satChannelMap: String? = nil,
        track: Track = .empty,
        state: RoomState = .active,
        battery: Battery? = nil,
        macAddress: String? = nil,
        location: URL? = nil,
        wirelessMode: Int = 1,
        wirelessLeafOnly: Bool = false,
        behindWifiExtender: Bool = false,
        wifiEnabled: Bool = true,
        ethernetEnabled: Bool = false,
        voiceConfigState: Int = 0,
        micEnabled: Bool = false,
        airPlayEnabled: Bool = false,
        invisible: Bool = false,
        subs: [Sub] = [],
        info: DeviceInfo? = nil
    ) {
        self.id = id
        self.ip = ip
        self.name = name
        self.channelMap = channelMap
        self.satChannelMap = satChannelMap
        self.track = track
        self.state = state
        self.battery = battery
        self.macAddress = macAddress
        self.location = location
        self.wirelessMode = wirelessMode
        self.wirelessLeafOnly = wirelessLeafOnly
        self.behindWifiExtender = behindWifiExtender
        self.wifiEnabled = wifiEnabled
        self.ethernetEnabled = ethernetEnabled
        self.voiceConfigState = voiceConfigState
        self.micEnabled = micEnabled
        self.airPlayEnabled = airPlayEnabled
        self.invisible = invisible
        self.subs = subs
        self.info = info
    }

    @MainActor
    public func updateVolume(volume: Double) {
        lock.withLock { 
            DispatchQueue.main.async { [weak self] in
                self?.volume = volume
            }
        }
    }
}

extension Room: Hashable {
    public static func == (lhs: Room, rhs: Room) -> Bool {
        lhs.id == rhs.id &&
        lhs.ip == rhs.ip &&
        lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(ip)
        hasher.combine(state)
        hasher.combine(macAddress)
    }
}


extension Room: CustomStringConvertible {
    public var description: String {
        "\(name): \(volume)% [\(id)] [\(ip)]"
    }
}

extension Room {
    public static let garage = Room(id: "RINCON_B8E937525BB001400", ip: "192.168.4.50", name: "Garage" )
    public static let gym = Room(id: "RINCON_7828CAC7352E01400", ip: "192.168.4.49", name: "Gym")
    public static let theater = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Theater", track: Track(trackID: "134"))
    public static let livingRoom = Room(id: "RINCON_949F3E6FBAE401400", ip: "192.168.4.48", name: "Living Room")
    public static let garage_kitchen_display = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Kitchen")
}
