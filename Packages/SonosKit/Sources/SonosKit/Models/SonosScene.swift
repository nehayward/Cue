import Foundation
import Observation

public struct SonosScene: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String = ""
    public var rooms: [SceneRoom] = []
    public var volumeOnly: Bool?
    public var playableContent: PlayableContent?

    public init(
        id: UUID = UUID(),
        name: String,
        rooms: [SceneRoom],
        volumeOnly: Bool = false,
        playableContent: PlayableContent? = nil
    ) {
        self.id = id
        self.name = name
        self.rooms = rooms
        self.volumeOnly = volumeOnly
        self.playableContent = playableContent
    }

    public static func == (lhs: SonosScene, rhs: SonosScene) -> Bool {
        lhs.id == rhs.id
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

    public static func == (lhs: SceneRoom, rhs: SceneRoom) -> Bool {
        lhs.id == rhs.id
    }
}
