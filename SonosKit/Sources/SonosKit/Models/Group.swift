import Observation

@Observable
public class Group: Identifiable {
    public var id: String { ipAddress }
    public let name: String
    public let ipAddress: String
    public var volume: Double = 0
    public var isPlaying: Bool = false

    public init(name: String, ipAddress: String, volume: Double, isPlaying: Bool) {
        self.name = name
        self.ipAddress = ipAddress
        self.volume = volume
        self.isPlaying = isPlaying
    }
}
