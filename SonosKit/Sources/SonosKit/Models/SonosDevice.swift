import Observation

@Observable
public class SonosDevice: Identifiable {
    public var id: String { ipAddress }
    public let name: String
    public let ipAddress: String
    public var volume: Double = 0

    public init(name: String, ipAddress: String, volume: Double = 0) {
        self.name = name
        self.ipAddress = ipAddress
        self.volume = volume
    }
}
