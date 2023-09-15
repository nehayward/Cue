import Foundation
import Observation

@Observable
public final class Room: Identifiable, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Room\(UUID().uuidString)")

    public let id: String
    public let ip: String
    public let name: String

    public var volume: Double = 0
    public var isPlaying: Bool = false
    public var track: Track = .empty

    public init(id: String, ip: String, name: String) {
        self.id = id
        self.ip = ip
        self.name = name
    }

    public func updateVolume(volume: Double) {
        queue.sync {
            self.volume = volume
        }
    }
}

extension Room: Hashable {
    public static func == (lhs: Room, rhs: Room) -> Bool {
        lhs.id == rhs.id &&
        lhs.ip == rhs.ip &&
        lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
//        hasher.combine(volume)
//        hasher.combine(isPlaying)
    }
}


extension Room: CustomStringConvertible {
    public var description: String {
        "\(name): \(volume)% [\(id)]"
    }
}


extension Room {
    public static let garage = Room(id: "RINCON_B8E937525BB001400", ip: "192.168.4.50", name: "Garage")
}
