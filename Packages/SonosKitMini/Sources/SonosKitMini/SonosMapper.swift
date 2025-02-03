import Foundation

extension ZoneGroup {
    var toGroup: SonosGroup? {
        let speakerSubs = members.filter { $0.zoneName.lowercased().contains("sub") }
        let subs: [Sub] = speakerSubs.map {
            var ip: String = ""
            let pattern = #"http://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):"#
            if let range = $0.location.range(of: pattern, options: .regularExpression) {
                let match = String($0.location[range])
                // Remove the "http://" and ":" parts
                let ipAddress = match.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: ":", with: "")
                ip = ipAddress
            }
            return Sub(name: $0.zoneName, ip: ip)
        }

        let rooms = members.compactMap { $0.toRoom(groupID: coordinator, speakerSubs: subs)}
        if rooms.isEmpty {
            return nil
        }

        guard let coordinatorRoom = rooms.first(where: { $0.id == coordinator }) else { return nil }

        return SonosGroup(id: id,
                         coordinatorID: coordinator,
                         rooms: rooms,
                         coordinatorRoom: coordinatorRoom
        )
    }
}

extension ZoneGroupMember {
    func toRoom(groupID: String, speakerSubs: [Sub]) -> SonosRoom? {
        guard !invisible else { return nil }
        let components = URLComponents(string: location)
        guard let ip = components?.host else { return nil }
        let theaterSubs = satellites.filter { $0.zoneName.lowercased().contains("sub")}

        let subs: [Sub] = theaterSubs.map {
            var ip: String = ""
            let pattern = #"http://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):"#
            if let range = $0.location.range(of: pattern, options: .regularExpression) {
                let match = String($0.location[range])
                // Remove the "http://" and ":" parts
                let ipAddress = match.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: ":", with: "")
                ip = ipAddress
            }
            return Sub(name: $0.zoneName, ip: ip)
        }

        return SonosRoom(
            id: UUID,
            groupID: groupID,
            ip: ip,
            name: zoneName,
            channelMap: channelMap,
            satChannelMap: satChannelMap,
            battery: Battery(info: info),
            location: URL(string: location),
            wirelessMode: wirelessMode,
            wirelessLeafOnly: wirelessLeafOnly,
            behindWifiExtender: behindWifiExtender,
            wifiEnabled: wifiEnabled,
            ethernetEnabled: ethernetEnabled,
            voiceConfigState: voiceConfigState,
            micEnabled: micEnabled,
            airPlayEnabled: airPlayEnabled,
            invisible: invisible,
            subs: speakerSubs + subs
        )
    }

    func coordinatorRoom(coordinatorID: String) -> SonosRoom? {
        guard UUID == coordinatorID else { return nil }
        guard !invisible else { return nil }
        let components = URLComponents(string: location)
        guard let ip = components?.host else { return nil }
        return SonosRoom(
            id: UUID,
            groupID: UUID,
            ip: ip,
            name: zoneName,
            channelMap: channelMap,
            satChannelMap: satChannelMap,
            battery: Battery(info: info),
            location: URL(string: location),
            wirelessMode: wirelessMode,
            wirelessLeafOnly: wirelessLeafOnly,
            behindWifiExtender: behindWifiExtender,
            wifiEnabled: wifiEnabled,
            ethernetEnabled: ethernetEnabled,
            voiceConfigState: voiceConfigState,
            micEnabled: micEnabled,
            airPlayEnabled: airPlayEnabled,
            invisible: invisible
        )
    }
}

extension SonosRoom {
    var toSonosDevice: SonosDevice? {
        return SonosDevice(
            name: name,
            id: id,
            ip: ip,
            isHidden: id != groupID,
            channelMap: channelMap,
            satChannelMap: satChannelMap,
            state: .active,
            battery: battery,
            location: location,
            wirelessMode: wirelessMode,
            wirelessLeafOnly: wirelessLeafOnly,
            behindWifiExtender: behindWifiExtender,
            wifiEnabled: wifiEnabled,
            ethernetEnabled: ethernetEnabled,
            voiceConfigState: voiceConfigState,
            micEnabled: micEnabled,
            airPlayEnabled: airPlayEnabled
        )
    }
}
//
//extension VanishedDevice {
//    var toGroup: GroupRoom? {
//        guard let IP, let name, let info, let reason, let macAddress else { return nil }
//
//        let room = Room(id: id, ip: IP, name: name, state: RoomState(reason: reason), battery: Battery(info: info), macAddress: macAddress)
//        return GroupRoom(id: id,
//                         coordinatorID: id,
//                         rooms: [room],
//                         coordinatorRoom: room
//        )
//    }
//}
//
//extension Room {
//    public var toGroup: GroupRoom {
//        return GroupRoom(id: id,
//                         coordinatorID: id,
//                         rooms: [self],
//                         coordinatorRoom: self
//        )
//    }
//}
