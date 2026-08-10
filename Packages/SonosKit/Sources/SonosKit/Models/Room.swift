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
    /// True while the transport reports TRANSITIONING — e.g. right after new
    /// content is queued and before playback actually starts. UI uses this to
    /// pulse the play/pause button.
    public var isTransitioning: Bool = false
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

    /// Model numbers (`DeviceInfo.model`) with the levelled Arc Ultra speech
    /// enhancement rather than the on/off `DialogLevel` every other soundbar has.
    /// The number is stable where `modelDisplayName` moves with locale and renames —
    /// the substring match below is the fallback for models not catalogued here.
    private static let arcUltraModelNumbers: Set<String> = ["S45"] // Sonos Arc Ultra

    public var isArcUltra: Bool {
        guard let info else { return false }
        let model = info.model.trimmingCharacters(in: .whitespaces).uppercased()
        if Self.arcUltraModelNumbers.contains(model) { return true }
        return info.modelDisplayName.lowercased().contains("arc ultra")
    }

    /// `nil` until the model is known. Guessing "not an Arc Ultra" from a missing
    /// model sends the wrong EQ command, so callers that can probe the speaker
    /// should treat `nil` as "ask it" rather than as `false`.
    public var isArcUltraIfKnown: Bool? {
        info == nil ? nil : isArcUltra
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

    /// Where a playback-state write came from. The sources have very different
    /// latencies and authority, and until they went through one funnel they
    /// silently fought each other.
    public enum PlaybackStateSource: String {
        /// Pushed by the speaker over the WebSocket, ~100 ms after the fact.
        case socket
        /// A SOAP read — the pulse, a Live Activity refresh, a group sweep.
        /// Always a request/response behind whatever just happened.
        case poll
        /// An optimistic write from a user action, before the speaker confirms.
        case localCommand
    }

    /// The single way `isPlaying` should be written.
    ///
    /// Precedence: a pushed or user-initiated state wins over a polled one for
    /// two seconds. A SOAP response captured *before* a pause lands *after* the
    /// socket reported it, and would otherwise flip the flag back — invisible on
    /// screen, where the next poll corrects it, but on a Lock Screen card it
    /// reads as playback flickering.
    public func setPlaying(_ playing: Bool, source: PlaybackStateSource) {
        if source != .poll {
            // Stamped even when the value is unchanged: what matters is that a
            // fast source just spoke, not that it changed its mind.
            playbackStateStampedAt = .now
        } else if hasFreshPlaybackState, isPlaying != playing {
            return
        }
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
