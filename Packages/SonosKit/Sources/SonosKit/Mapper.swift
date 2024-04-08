import Foundation

extension ZoneGroup {
    var toGroup: GroupRoom? {
        let rooms = zoneGroupMembers.compactMap(\.toRoom)
        if rooms.isEmpty {
            return nil
        }

        guard let coordinatorRoom = rooms.first(where: { $0.id == coordinator }) else { return nil }

        return GroupRoom(id: ID,
                         coordinatorID: coordinator,
                         rooms: rooms,
                         coordinatorRoom: coordinatorRoom
        )
    }
}

extension ZoneGroupMember {
    var toRoom: Room? {
        guard !invisible else { return nil }
        let components = URLComponents(string: location)
        guard let ip = components?.host else { return nil }
        return Room(id: UUID, ip: ip, name: zoneName, battery: Battery(info: info))
    }

    func coordinatorRoom(coordinatorID: String) -> Room? {
        guard UUID == coordinatorID else { return nil }
        guard !invisible else { return nil }
        let components = URLComponents(string: location)
        guard let ip = components?.host else { return nil }
        return Room(id: UUID, ip: ip, name: zoneName, battery: Battery(info: info))
    }
}

extension VanishedDevice {
    var toGroup: GroupRoom? {
        guard let IP, let name, let info, let reason, let macAddress else { return nil }

        let room = Room(id: id, ip: IP, name: name, state: RoomState(reason: reason), battery: Battery(info: info), macAddress: macAddress)
        return GroupRoom(id: id,
                         coordinatorID: id,
                         rooms: [room],
                         coordinatorRoom: room
        )
    }
}
