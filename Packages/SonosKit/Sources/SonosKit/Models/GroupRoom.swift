import Foundation
import Observation
import os

@Observable
public final class GroupRoom: Identifiable, @unchecked Sendable {
    public var coordinatorRoom: Room
    public let id: String
    public let coordinatorID: String
    public var rooms: [Room] = []
    public var TVMode: Bool { playbackService == .tv }
    public var isCrossfaded: Bool? = nil
    public var tvSettings: TVSettings?
    public var playMode: PlayMode = .normal
    public var isMuted: Bool = false
    public var ip: String { coordinatorRoom.ip }
    public var isEditingVolume: Bool = false
    public var isEditingPlayback: Bool = false
    public var playbackService: PlaybackService = .unknown

    /// Whether `track` is the row currently playing from the queue. Matched by queue
    /// position — the unique 1-based queue index at render time (not stable across
    /// reorders) — and gated on playing from the queue.
    public func isNowPlaying(_ track: PlayableContent) -> Bool {
        track.metadata?.position == coordinatorRoom.track.position && playbackService == .queue
    }
    public var availableActions: AvailableActions = []
    public var groupVolume: Double = 0
    public var audioQuality: SonosTrackQuality? = nil

    public init(
        id: String,
        coordinatorID: String,
        rooms: [Room],
        coordinatorRoom: Room,
        tvSettings: TVSettings? = nil
    ) {
        self.id = id
        self.coordinatorID = coordinatorID
        self.rooms = rooms
        self.coordinatorRoom = coordinatorRoom
        self.tvSettings = tvSettings
    }
}

extension GroupRoom {
    public var isActive: Bool {
        coordinatorRoom.state == .active
    }

    /// Stable id-only fingerprint for detecting topology changes (coordinator + sorted member ids).
    /// Ignores volatile state like track, playback, battery, name.
    public var topologyKey: String {
        "\(coordinatorID):\(rooms.map(\.id).sorted().joined(separator: ","))"
    }

    public var nameWithCount: String {
        switch rooms.count {
        case 0...1:
            "\(coordinatorRoom.name)"
        case 1...2:
            "\(coordinatorRoom.name) + \(rooms.filter { $0.id != coordinatorRoom.id }.map(\.name).joined())"
        default:
            "\(coordinatorRoom.name) + \(rooms.count - 1)"
        }
    }
}


extension GroupRoom: Hashable {
    public static func == (lhs: GroupRoom, rhs: GroupRoom) -> Bool {
        lhs.coordinatorID == rhs.coordinatorID &&
        lhs.rooms == rhs.rooms &&
        lhs.coordinatorRoom == rhs.coordinatorRoom &&
        lhs.TVMode == rhs.TVMode &&
        lhs.nameWithCount == rhs.nameWithCount
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(coordinatorID)
        hasher.combine(rooms)
        hasher.combine(coordinatorRoom)
        hasher.combine(TVMode)
        hasher.combine(nameWithCount)
    }
}


extension GroupRoom {
    static var debug: [GroupRoom] = []
    public static let gym = GroupRoom(id: "RINCON_7828CAC7352E01400:857060900",
                                         coordinatorID: Room.gym.id,
                                         rooms: [.gym],
                                         coordinatorRoom: .gym)
    

    public static let garage = GroupRoom(id: "RINCON_B8E937525BB001400:931790658",
                                         coordinatorID: Room.garage.id,
                                         rooms: [.garage],
                                         coordinatorRoom: .garage)

    public static let theater = GroupRoom(id: "RINCON_48A6B80D8FB401400:2447655188",
                                          coordinatorID: Room.theater.id,
                                          rooms: [.theater],
                                          coordinatorRoom: .theater,
                                          tvSettings: TVSettings(nightMode: true, dialogLevel: false, audioInputFormat: .unknown))

    public static let garage_kitchen_display = GroupRoom(id: "RINCON_B8E937525BB001400:931790658",
                                         coordinatorID: Room.garage_kitchen_display.id,
                                         rooms: [.garage_kitchen_display],
                                         coordinatorRoom: .garage_kitchen_display)

    public static let garagePlusTheater = GroupRoom(id: "RINCON_B8E937525BB001400:931790658",
                                         coordinatorID: Room.garage.id,
                                                    rooms: [.garage, .theater],
                                         coordinatorRoom: .garage)
    
   
    public static let theaterFixed = GroupRoom(id: "RINCON_48A6B80D8FB401400:2447655188",
                                          coordinatorID: Room.theaterFixed.id,
                                          rooms: [.theaterFixed],
                                          coordinatorRoom: .theaterFixed,
                                          tvSettings: TVSettings(nightMode: true, dialogLevel: false, audioInputFormat: .unknown))
}
