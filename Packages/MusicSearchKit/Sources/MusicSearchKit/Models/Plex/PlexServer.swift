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

    public var nonLocalURIs: [String] {
        connections
            .filter { !$0.local }
            .filter { !$0.address.lowercased().contains("quick") }
            .filter { $0.port != 443 }
            .sorted {
                // Prioritize 32400
                ($0.port == 32400 ? 0 : 1) < ($1.port == 32400 ? 0 : 1)
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
