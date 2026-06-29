import Foundation

public struct PlexServer: Codable {
    public let name: String
    public let product: String?
    public let productVersion: String?
    public let platform: String?
    public let platformVersion: String?
    public let device: String?
    public let clientIdentifier: String?
    public let createdAt: String?
    public let lastSeenAt: String?
    public let provides: String?
    public let ownerId: Int?
    public let sourceTitle: String?
    public let publicAddress: String?
    public let accessToken: String?
    public let owned: Bool?
    public let home: Bool?
    public let synced: Bool?
    public let relay: Bool?
    public let presence: Bool?
    public let httpsRequired: Bool?
    public let publicAddressMatches: Bool?
    public let dnsRebindingProtection: Bool?
    public let natLoopbackSupported: Bool?
    public let connections: [PlexConnection]

    public var localURIs: [String] {
        connections.filter({ $0.local }).map(\.uri)
    }

    private static let preferredPorts = [8443, 32400, 443]

    public var nonLocalURIs: [String] {
        connections
            .filter { !$0.local }
            .filter { !$0.address.lowercased().contains("quick") }
            .sorted {
                // Relay connections proxy through plex.tv at a throttled
                // bandwidth cap, so always prefer direct remote connections.
                let r0 = $0.relay ?? false
                let r1 = $1.relay ?? false
                if r0 != r1 { return !r0 }
                let p0 = Self.preferredPorts.firstIndex(of: $0.port ?? -1) ?? Int.max
                let p1 = Self.preferredPorts.firstIndex(of: $1.port ?? -1) ?? Int.max
                return p0 < p1
            }
            .map(\.uri)
    }

    func baseURL(preferring connectionType: PlexAPI.ConnectionPreference) -> URL? {
        switch connectionType {
        case .local:
            guard let connection = localURIs.first else { 
                return nil
            }
            return URL(string: connection)
        case .nonLocal:
            guard let connection = nonLocalURIs.first else { 
                // Fallback to local if no non-local connection available
                return localURIs.first.flatMap { URL(string: $0) }
            }
            return URL(string: connection)
        }
    }
}

public struct PlexConnection: Codable {
    let protocolType: String?
    let address: String
    let port: Int?
    let uri: String
    let local: Bool
    let relay: Bool?
    let IPv6: Bool?

    enum CodingKeys: String, CodingKey {
        case protocolType = "protocol"
        case address, port, uri, local, relay, IPv6
    }
}
