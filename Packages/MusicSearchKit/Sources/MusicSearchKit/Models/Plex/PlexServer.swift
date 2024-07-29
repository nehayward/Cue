import Foundation

public struct PlexServer: Codable {
    public let name: String
    public let product: String
    public let productVersion: String
    public let platform: String
    public let platformVersion: String
    public let device: String
    public let clientIdentifier: String
    public let createdAt: String
    public let lastSeenAt: String
    public let provides: String
    public let ownerId: Int?
    public let sourceTitle: String?
    public let publicAddress: String
    public let accessToken: String?
    public let owned: Bool
    public let home: Bool
    public let synced: Bool
    public let relay: Bool
    public let presence: Bool
    public let httpsRequired: Bool
    public let publicAddressMatches: Bool
    public let dnsRebindingProtection: Bool?
    public let natLoopbackSupported: Bool?
    public let connections: [PlexConnection]

    var baseURL: URL? {
        guard let connection = connections.filter({ !$0.local }).first else { return nil }
        return URL(string: "\(connection.uri)")
    }
}

public struct PlexConnection: Codable {
    let protocolType: String
    let address: String
    let port: Int
    let uri: String
    let local: Bool
    let relay: Bool
    let IPv6: Bool

    enum CodingKeys: String, CodingKey {
        case protocolType = "protocol"
        case address, port, uri, local, relay, IPv6
    }
}
