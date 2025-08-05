import Foundation
import Observation

public struct SonosScene: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var rooms: [SceneRoom] = []
    public var volumeOnly: Bool
    public var playableContent: PlayableContent?
    public var playMode: PlayMode?
    public var position: SonosQueuePlacement?
    
    public var description: String {
        let groupedRooms = rooms.map(\.name).joined(separator: ", ")
        let roomVolumes = rooms.map { "\($0.name) set to \(Int($0.volume))%" }.joined(separator: "\n")
        
        var details = rooms.count > 1
        ? "Grouped \(groupedRooms)\n\(roomVolumes)"
        : "\(roomVolumes)"
        
        if let content = playableContent {
            details += ", currently playing \(content.title) by \(content.subtitle)"
        }
        
        return details + "."
    }

    public init(
        id: UUID = UUID(),
        name: String = "",
        rooms: [SceneRoom] = [],
        volumeOnly: Bool = false,
        playableContent: PlayableContent? = nil,
        playMode: PlayMode = .normal,
        position: SonosQueuePlacement = .next
    ) {
        self.id = id
        self.name = name
        self.rooms = rooms
        self.volumeOnly = volumeOnly
        self.playableContent = playableContent
        self.playMode = playMode
        self.position = position
    }
}

public struct SceneRoom: Codable, Hashable {
    public let id: String
    public let ip: String
    public let name: String
    public var volume: Double = 0

    public init(id: String, ip: String, name: String, volume: Double) {
        self.id = id
        self.ip = ip
        self.name = name
        self.volume = volume
    }
}
