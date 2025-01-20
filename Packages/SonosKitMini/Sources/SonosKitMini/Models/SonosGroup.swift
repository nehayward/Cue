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


//
//extension SonosGroup {
//    static var debug: [SonosGroup] = []
//    public static let gym = Self(id: "RINCON_7828CAC7352E01400:857060900",
//                                 coordinatorID: SonosRoom.gym.id,
//                                         rooms: [.gym],
//                                         coordinatorRoom: .gym)
//    
//
//    public static let garage = Self(id: "RINCON_B8E937525BB001400:931790658",
//                                         coordinatorID: SonosRoom.garage.id,
//                                         rooms: [.garage],
//                                         coordinatorRoom: .garage)
//
//    public static let theater = Self(id: "RINCON_48A6B80D8FB401400:2447655188",
//                                          coordinatorID: SonosRoom.theater.id,
//                                          rooms: [.theater],
//                                          coordinatorRoom: .theater,
//                                        tvSettings: SonosTVSettings(nightMode: true, dialogLevel: false, audioInputFormat: .unknown))
//
//    public static let garage_kitchen_display = Self(id: "RINCON_B8E937525BB001400:931790658",
//                                         coordinatorID: SonosRoom.garage_kitchen_display.id,
//                                         rooms: [.garage_kitchen_display],
//                                         coordinatorRoom: .garage_kitchen_display)
//
//    public static let garagePlusTheater = Self(id: "RINCON_B8E937525BB001400:931790658",
//                                         coordinatorID: SonosRoom.garage.id,
//                                                    rooms: [.garage, .theater],
//                                         coordinatorRoom: .garage)
//}
