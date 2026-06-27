import Foundation

public struct SonosHousehold: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var lastKnownIP: String
    /// All speaker IPs seen for this household. Probed concurrently on reconnect
    /// so a removed or DHCP-reassigned speaker doesn't block the working ones.
    public var knownIPs: Set<String>
    public var name: String
    public var lastConnected: Date

    public init(id: String, lastKnownIP: String, name: String, lastConnected: Date = .now) {
        self.id = id
        self.lastKnownIP = lastKnownIP
        self.knownIPs = [lastKnownIP]
        self.name = name
        self.lastConnected = lastConnected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        lastKnownIP = try container.decode(String.self, forKey: .lastKnownIP)
        name = try container.decode(String.self, forKey: .name)
        lastConnected = try container.decode(Date.self, forKey: .lastConnected)
        // Migration: knownIPs absent in older stored data — seed from lastKnownIP.
        knownIPs = try container.decodeIfPresent(Set<String>.self, forKey: .knownIPs) ?? [lastKnownIP]
    }
}
