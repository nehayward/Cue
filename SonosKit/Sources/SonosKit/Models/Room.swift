import Foundation
import Observation

@Observable
public class Room: Identifiable {
    public let id: String
    public let ip: String
    public let name: String
    
    public var volume: Double = 0
    public var isPlaying: Bool = false
    public var track: Track = .init(name: "", artist: "", album: "", artworkURL: nil, musicService: .apple, duration: .zero, playbackPosition: .zero)

    public init(id: String, ip: String, name: String) {
        self.id = id
        self.ip = ip
        self.name = name
    }
}

extension Room: Hashable {
    public static func == (lhs: Room, rhs: Room) -> Bool {
        lhs.id == rhs.id &&
        lhs.ip == rhs.ip &&
        lhs.name == rhs.name &&
        lhs.volume == rhs.volume &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.track == rhs.track
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(ip)
        hasher.combine(name)
        hasher.combine(volume)
        hasher.combine(isPlaying)
        hasher.combine(track)
    }
}


extension Room: CustomStringConvertible {
    public var description: String {
        "\(name): \(volume)% [\(id)]"
    }
}
