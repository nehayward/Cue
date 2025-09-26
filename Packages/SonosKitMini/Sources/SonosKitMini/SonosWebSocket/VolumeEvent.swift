import Foundation

public struct SocketInfo: Codable {
    let playerId: String?
    let groupId: String?
    let type: String?
    let householdId: String?
}

public struct PlayerVolumeState: Codable {
    public let muted: Bool
    public let fixed: Bool
    public let volume: Int
    public let objectType: String
    
    enum CodingKeys: String, CodingKey {
        case muted, fixed, volume
        case objectType = "_objectType"
    }
}

public struct VolumeEvent {
    public let info: SocketInfo
    public let volumeState: PlayerVolumeState?

    // Decode from the array format
    static func decode(from data: Data) throws -> VolumeEvent {
        // Decode as an array of generic JSON objects
        let decoder = JSONDecoder()
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        var info: SocketInfo?
        var state: PlayerVolumeState?

        for item in array {
            // Try decoding info
            if info == nil, let infoData = try? JSONSerialization.data(withJSONObject: item),
               let i = try? decoder.decode(SocketInfo.self, from: infoData) {
                info = i
                continue
            }

            // Try decoding state
            if state == nil, let stateData = try? JSONSerialization.data(withJSONObject: item),
               let s = try? decoder.decode(PlayerVolumeState.self, from: stateData),
               s.objectType != "" {
                state = s
                continue
            }
        }

        guard let socketInfo = info, let type = info?.type, type.lowercased().contains("volume") else {
            throw NSError(domain: "VolumeEvent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing SocketInfo"])
        }

        return VolumeEvent(info: socketInfo, volumeState: state)
    }
}
