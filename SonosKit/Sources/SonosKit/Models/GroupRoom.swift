import Foundation
import Observation

@Observable
public class GroupRoom: Identifiable {
    public let id: String
    public let coordinatorID: String
    public var rooms: [Room] = []
    public var tvMode: Bool = false
    public var tvSettings: TVSettings? = nil
    public var groupVolume: Double = 0
    
    public var coordinatorRoom: Room {
        rooms.first { room in
            room.id == coordinatorID
        }!
    }

    public init(id: String, coordinatorID: String, rooms: [Room]) {
        self.id = id
        self.coordinatorID = coordinatorID
        self.rooms = rooms
    }
}

extension GroupRoom: Hashable {
    public static func == (lhs: GroupRoom, rhs: GroupRoom) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinatorID == rhs.coordinatorID &&
        lhs.rooms.count == rhs.rooms.count
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinatorID)
        hasher.combine(rooms)
    }
}


extension GroupRoom {
    static var debug: [GroupRoom] = []
}
