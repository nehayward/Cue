import Foundation
import OrderedCollections
import Observation
import os

@Observable
public final class Room: Identifiable, @unchecked Sendable {
    public let id: String
    public let ip: String
    public let name: String
    public let channelMap: String?
    public let satChannelMap: String?
    public var volume: Double = 0
    public var isMuted: Bool = false
    public var isPlaying: Bool = false
    public var track: Track = .empty
    /// Current playback position (ms) as last reported by the device or set by a
    /// local seek. Lives on `Room` rather than `Track` so the high-frequency
    /// position pulses from Sonos don't fire `Room.track` observation and
    /// invalidate every consumer reading any track field.
    public var playbackPosition: TimeInterval = 0
    /// When `isPlaying` was last set from a pushed (WebSocket) event. Read
    /// through `hasFreshPlaybackState` — see `markPlaybackState`.
    @ObservationIgnored public private(set) var playbackStateStampedAt: Date = .distantPast
    /// Radio Station Name
    public var radioStation: String?
    public var isEditingVolume: Bool = false
    public var isOutputFixed: Bool = false
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
    /// For vanished/sleeping speakers, the UTC timestamp Sonos last
    /// reported them as reachable. Nil for currently-active rooms.
    public var lastSeen: Date? = nil
    public var subs: [Sub] = []
    public var queue: OrderedSet<PlayableContent> = []
    public var queueTotal: Int = 0
    public var container: SonosContainer?

    // MARK: Settings
    public var settings = SpeakerSettings(isSet: false)
    public var theaterSettings = TheaterSettings(isSet: false)

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
    
    public var supportsLineIn: Bool {
        guard let info else { return false }
        // Prefer the device-reported capability — it's authoritative across firmware/models.
        if let capabilities = info.capabilities {
            return capabilities.contains("LINE_IN")
        }
        // Fallback when capabilities haven't been reported yet. "Era" and "Move 2" stay
        // broad — every Era (100/100 SL/300) and Move 2 supports line-in via the USB-C
        // adapter. "Play:5" and the 2026 portable "Play" both support it, but must be
        // matched precisely: the bare "Play" substring also caught Play:1/Play:3/Playbar/
        // Playbase, which have no line-in and wrongly surfaced the "Switch to Line In" action.
        let model = info.modelDisplayName
        // New portable "Sonos Play" — exact (last-token) match so we don't catch its siblings.
        if model.split(separator: " ").last == "Play" { return true }
        let keywords = ["Amp", "Connect", "Port", "Five", "Play:5", "Era", "Move 2"]
        return keywords.contains(where: model.contains)
    }
    
    public var supportsFixedOutput: Bool {
        let keywords = ["Port", "Connect"]
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
        isOutputFixed: Bool = false,
        subs: [Sub] = [],
        info: DeviceInfo? = nil,
        container: SonosContainer? = nil,
        lastSeen: Date? = nil
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
        self.isOutputFixed = isOutputFixed
        self.invisible = invisible
        self.subs = subs
        self.info = info
        self.container = container
        self.lastSeen = lastSeen
    }
}

extension Room {
    public func updatePlaybackPosition(_ newValue: TimeInterval) {
        playbackPosition = newValue
    }

    /// Sets `isPlaying` and records when, marking it as pushed to us rather than
    /// polled for.
    ///
    /// Two kinds of source write this: the WebSocket, which the speaker pushes
    /// within ~100 ms of the transport actually changing, and SOAP reads, which
    /// are a request/response behind. When both are live — the Lock Screen
    /// session holds a socket while `LiveActivityManager` and the pulse keep
    /// polling — a SOAP response captured *before* a pause lands *after* the
    /// socket reported it, flipping the flag back. On screen the next poll
    /// corrects it; on a Lock Screen card driven by this flag it reads as
    /// playback flickering between states.
    public func markPlaybackState(_ playing: Bool) {
        playbackStateStampedAt = .now
        guard isPlaying != playing else { return }
        isPlaying = playing
    }

    /// Whether a pushed playback state landed recently enough that a SOAP read
    /// shouldn't overwrite it. Poll intervals here are 500–800 ms, so two
    /// seconds covers a response that was already in flight.
    public var hasFreshPlaybackState: Bool {
        Date.now.timeIntervalSince(playbackStateStampedAt) < 2
    }
}

extension Room: Hashable {
    public static func == (lhs: Room, rhs: Room) -> Bool {
        lhs.id == rhs.id &&
        lhs.ip == rhs.ip &&
        lhs.name == rhs.name &&
        lhs.track.id == rhs.track.id &&
        lhs.track.artist == rhs.track.artist &&
        lhs.track.song == rhs.track.song &&
        lhs.radioStation == rhs.radioStation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(ip)
        hasher.combine(state)
        hasher.combine(macAddress)
        hasher.combine(track.id)
        hasher.combine(track.artist)
        hasher.combine(track.song)
        hasher.combine(radioStation)
    }
}


extension Room: CustomStringConvertible {
    public var description: String {
        "\(name): \(volume)% [\(id)] [\(ip)]"
    }
}

extension Room {
    public static let garage = Room(
        id: "RINCON_B8E937525BB001400",
        ip: "192.168.4.50",
        name: "Garage",
        container: .init(
            images: nil,
            objectType: nil,
            service: .init(
                id: "12",
                name: "Spotify",
                images: [],
                objectType: nil
            ),
            htInputFormat: nil,
            type: "playlist",
            name: "Mood Booster",
            id: .init(
                accountId: nil,
                serviceId: "12",
                objectId: "spotify:playlist:37i9dQZF1DX3rxVfibe1L0",
                objectType: ""
            )
        )
    )
    public static let gym = Room(id: "RINCON_7828CAC7352E01400", ip: "192.168.4.49", name: "Gym")
    public static let theater = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Theater", track: Track(trackID: "134"))
    public static let theaterFixed = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Theater", track: Track(trackID: "134"), isOutputFixed: true)
    public static let livingRoom = Room(id: "RINCON_949F3E6FBAE401400", ip: "192.168.4.48", name: "Living Room")
    public static let garage_kitchen_display = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Kitchen")
}
