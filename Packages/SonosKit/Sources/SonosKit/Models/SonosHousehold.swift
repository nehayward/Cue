import Foundation

public struct SonosHousehold: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var lastKnownIP: String
    public var name: String
    public var lastConnected: Date

    public init(id: String, lastKnownIP: String, name: String, lastConnected: Date = .now) {
        self.id = id
        self.lastKnownIP = lastKnownIP
        self.name = name
        self.lastConnected = lastConnected
    }
}
