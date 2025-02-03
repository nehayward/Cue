import Foundation
import Observation
import os

@Observable
public class SonosGroup: Equatable, Identifiable, @unchecked Sendable {
    public var coordinatorRoom: SonosRoom
    public let id: String
    public let coordinatorID: String
    public var rooms: [SonosRoom] = []
    public var TVMode: Bool { playbackService == .tv }
    public var isCrossfaded: Bool? = nil
    public var tvSettings: SonosTVSettings?
    public var playMode: PlayMode = .normal
    public var isMuted: Bool = false
    public var ip: String { coordinatorRoom.ip }
    public var isEditingVolume: Bool = false
    public var isEditingPlayback: Bool = false
    public var playbackService: PlaybackService = .unknown
    public var availableActions: AvailableActions = []
    public var groupVolume: Double = 0

    public init(
        id: String,
        coordinatorID: String,
        rooms: [SonosRoom],
        coordinatorRoom: SonosRoom,
        tvSettings: SonosTVSettings? = nil
    ) {
        self.id = id
        self.coordinatorID = coordinatorID
        self.rooms = rooms
        self.coordinatorRoom = coordinatorRoom
        self.tvSettings = tvSettings
    }
}

extension SonosGroup: Hashable {
    public static func == (lhs: SonosGroup, rhs: SonosGroup) -> Bool {
        lhs.coordinatorID == rhs.coordinatorID &&
        lhs.rooms == rhs.rooms &&
        lhs.coordinatorRoom == rhs.coordinatorRoom
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(coordinatorID)
        hasher.combine(rooms)
        hasher.combine(coordinatorRoom)
    }
}

extension SonosGroup {
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
