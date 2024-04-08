import Foundation
import Observation
import os

@Observable
public final class Room: Identifiable, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()

    public let id: String
    public let ip: String
    public let name: String

    public var volume: Double = 0
    public var isMuted: Bool = false
    public var isPlaying: Bool = false
    public var track: Track = .empty
    public var isEditingVolume: Bool = false

    public var state: RoomState
    public var battery: Battery?
    public var macAddress: String?

    public init(id: String, ip: String, name: String, track: Track = .empty, state: RoomState = .active, battery: Battery? = nil, macAddress: String? = nil) {
        self.id = id
        self.ip = ip
        self.name = name
        self.track = track
        self.state = state
        self.battery = battery
        self.macAddress = macAddress
    }

    @MainActor
    public func updateVolume(volume: Double) {
        lock.withLock { 
            DispatchQueue.main.async { [weak self] in
                self?.volume = volume
            }
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
        hasher.combine(ip)
        hasher.combine(state)
        hasher.combine(macAddress)
    }
}


extension Room: CustomStringConvertible {
    public var description: String {
        "\(name): \(volume)% [\(id)]"
    }
}


extension Room {
    public static let garage = Room(id: "RINCON_B8E937525BB001400", ip: "192.168.4.50", name: "Garage")
    public static let theater = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Theater", track: Track(trackID: "134", TVMode: true))
    public static let garage_kitchen_display = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Kitchen")
}
