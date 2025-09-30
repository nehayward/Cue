import Foundation

public struct GroupInfo: Codable {
    public let id: String
    public let name: String?
    public let coordinatorId: String
    public let playerIds: [String]
    public let objectType: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, coordinatorId, playerIds
        case objectType = "_objectType"
    }
}

public struct PlayerDevice: Codable {
    public let objectType: String
    public let id: String
    public let serialNumber: String
    public let model: String
    public let modelDisplayName: String
    public let color: String
    public let capabilities: [String]
    public let apiVersion: String
    public let name: String
    public let websocketUrl: String
    public let softwareVersion: String
    
    enum CodingKeys: String, CodingKey {
        case id, serialNumber, model, modelDisplayName, color, capabilities, apiVersion, name, websocketUrl, softwareVersion
        case objectType = "_objectType"
    }
}

public struct PlayerInfo: Codable {
    public let objectType: String
    public let id: String
    public let name: String
    public let websocketUrl: String
    public let softwareVersion: String
    public let apiVersion: String
    public let capabilities: [String]
    public let deviceIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case id, name, websocketUrl, softwareVersion, apiVersion, capabilities, deviceIds
        case objectType = "_objectType"
    }
}

public struct GroupsResponse: Codable {
    public let objectType: String
    public let groups: [GroupInfo]
    public let players: [PlayerInfo]
    public let partial: Bool
    
    enum CodingKeys: String, CodingKey {
        case groups, players, partial
        case objectType = "_objectType"
    }
}

public struct GroupsSocketInfo: Codable {
    public let namespace: String
    public let householdId: String
    public let locationId: String?
    public let name: String
    public let type: String
}

public struct GroupEvent {
    public let info: GroupsSocketInfo
    public let groupsResponse: GroupsResponse?

    // Decode from the array format
    static func decode(from data: Data) throws -> Self? {
        // Decode as an array of generic JSON objects
        let decoder = JSONDecoder()
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        var info: GroupsSocketInfo?
        var response: GroupsResponse?

        for item in array {
            // Try decoding info
            if info == nil, let infoData = try? JSONSerialization.data(withJSONObject: item),
               let i = try? decoder.decode(GroupsSocketInfo.self, from: infoData) {
                info = i
                if info?.type != "groups" { return nil }
                continue
            }

            // Try decoding groups response
            if response == nil, let responseData = try? JSONSerialization.data(withJSONObject: item),
               let r = try? decoder.decode(GroupsResponse.self, from: responseData),
               r.objectType == "groups" {
                response = r
                continue
            }
        }

        guard let socketInfo = info else {
            throw NSError(domain: "GroupEvent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing SocketInfo"])
        }

        return Self(info: socketInfo, groupsResponse: response)
    }
}

