import Foundation
import Observation

@Observable
public final class GroupRoom: Identifiable, Sendable {
    private let queue = DispatchQueue(label: "GroupRoom\(UUID().uuidString)")
    public let coordinatorRoom: Room
    public let id: String
    public let coordinatorID: String
    public var rooms: [Room] = []
    public var tvMode: Bool = false
    public var tvSettings: TVSettings? = nil
    public var playMode: PlayMode = .normal
    public var isMuted: Bool = false
    public var ip: String { coordinatorRoom.ip }

    @ObservationIgnored
    private var privateGroupVolume: Double = 0

    public var groupVolume: Double {
        get {
            return queue.sync {
                return privateGroupVolume
            }
        }
        set {
            queue.sync {
                privateGroupVolume = newValue
            }
        }
    }

    public init(id: String, coordinatorID: String, rooms: [Room], coordinatorRoom: Room, tvSettings: TVSettings? = nil) {
        self.id = id
        self.coordinatorID = coordinatorID
        self.rooms = rooms
        self.coordinatorRoom = coordinatorRoom
        self.tvSettings = tvSettings
    }
}

extension GroupRoom: Hashable {
    public static func == (lhs: GroupRoom, rhs: GroupRoom) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinatorID == rhs.coordinatorID &&
        lhs.rooms == rhs.rooms
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(coordinatorID)
        hasher.combine(rooms)
    }
}


extension GroupRoom {
    static var debug: [GroupRoom] = []
    public static let garage = GroupRoom(id: "RINCON_B8E937525BB001400:931790658",
                                         coordinatorID: Room.garage.id,
                                         rooms: [.garage],
                                         coordinatorRoom: .garage)

    public static let theater = GroupRoom(id: "RINCON_48A6B80D8FB401400:2447655112",
                                          coordinatorID: Room.theater.id,
                                          rooms: [.theater],
                                          coordinatorRoom: .theater,
                                          tvSettings: TVSettings(nightMode: true, dialogLevel: false, audioInputFormat: .unknown))
}
