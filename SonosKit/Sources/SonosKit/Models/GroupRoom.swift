import Foundation
import Observation

@Observable
public final class GroupRoom: Identifiable, @unchecked Sendable {
    public let id: String
    public let coordinatorID: String
    public var rooms: [Room] = []
    public var tvMode: Bool = false
    public var tvSettings: TVSettings? = nil
    public var groupVolume: Double = 0
    public let coordinatorRoom: Room

    public init(id: String, coordinatorID: String, rooms: [Room], coordinatorRoom: Room) {
        self.id = id
        self.coordinatorID = coordinatorID
        self.rooms = rooms
        self.coordinatorRoom = coordinatorRoom
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
}
