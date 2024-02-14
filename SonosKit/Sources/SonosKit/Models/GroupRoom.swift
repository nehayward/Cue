import Foundation
import Observation
import os

@Observable
public final class GroupRoom: Identifiable, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    public var coordinatorRoom: Room
    public let id: String
    public let coordinatorID: String
    public var rooms: [Room] = []
    public var TVMode: Bool { coordinatorRoom.track.TVMode }
    public var tvSettings: TVSettings? {
        get {
            return lock.withLock {
                return privateTVSettings
            }
        }
        set {
            lock.withLock {
                DispatchQueue.main.async { [weak self] in
                    self?.privateTVSettings = newValue
                }
            }
        }
    }

    private var privateTVSettings: TVSettings? = nil
    public var playMode: PlayMode = .normal
    public var isMuted: Bool = false
    public var ip: String { coordinatorRoom.ip }
    public var isEditingVolume: Bool = false

    @ObservationIgnored
    private var privateGroupVolume: Double = 0

    public var groupVolume: Double {
        get {
            return lock.withLock {
                return privateGroupVolume
            }
        }
        set {
            lock.withLock {
                DispatchQueue.main.async { [weak self] in
                    self?.privateGroupVolume = newValue
                }
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

    public static let garage_kitchen_display = GroupRoom(id: "RINCON_B8E937525BB001400:931790658",
                                         coordinatorID: Room.garage_kitchen_display.id,
                                         rooms: [.garage_kitchen_display],
                                         coordinatorRoom: .garage_kitchen_display)

    public static let garagePlusTheater = GroupRoom(id: "RINCON_B8E937525BB001400:931790658",
                                         coordinatorID: Room.garage.id,
                                                    rooms: [.garage, .theater],
                                         coordinatorRoom: .garage)
}
