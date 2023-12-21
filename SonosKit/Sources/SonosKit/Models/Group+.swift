import Foundation

extension GroupRoom {
    public var nameWithCount: String { rooms.count > 1 ? "\(coordinatorRoom.name) + \(rooms.count - 1)" : "\(coordinatorRoom.name)" }
}
