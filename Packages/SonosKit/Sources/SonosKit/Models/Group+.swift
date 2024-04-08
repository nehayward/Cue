import Foundation

extension GroupRoom {
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
