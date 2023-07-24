import Foundation

extension ZoneGroup {
    var toGroup: GroupRoom? {
        let rooms = zoneGroupMembers.compactMap(\.toRoom)
        if rooms.isEmpty {
            return nil
        }
        
        return GroupRoom(id: ID,
                  coordinatorID: coordinator,
                  rooms: rooms
        )
    }
}

extension ZoneGroupMember {
    var toRoom: Room? {
        guard !invisible else { return nil }
        let components = URLComponents(string: location)
        guard let ip = components?.host else { return nil }
        return Room(id: UUID, ip: ip, name: zoneName)
    }

    func coordinatorRoom(coordinatorID: String) -> Room? {
        guard UUID == coordinatorID else { return nil }
        guard !invisible else { return nil }
        let components = URLComponents(string: location)
        guard let ip = components?.host else { return nil }
        return Room(id: UUID, ip: ip, name: zoneName)
    }
}
