import Foundation

public enum SonosServiceType: Codable, CaseIterable, Equatable, Hashable {
    case appleMusic
    case spotify
    case tidal
    case tunein
    case soundcloud
    case siriusXM
    case pandora
    case plex
    case bandcamp
    case unknown(String)
    
    public var rawValue: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .tidal: return "TIDAL"
        case .tunein: return "TuneIn"
        case .soundcloud: return "SoundCloud"
        case .siriusXM: return "SiriusXM"
        case .pandora: return "Pandora"
        case .plex: return "Plex"
        case .bandcamp: return "Bandcamp"
        case .unknown(let id): return "Unknown (\(id))"
        }
    }
    
    public static var allCases: [SonosServiceType] {
        [.appleMusic, .spotify, .tidal, .tunein, .soundcloud, .siriusXM, .pandora, .plex, .bandcamp, .unknown("")]
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case serviceId
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        switch rawValue {
        case "Apple Music": self = .appleMusic
        case "Spotify": self = .spotify
        case "TIDAL": self = .tidal
        case "TuneIn": self = .tunein
        case "SoundCloud": self = .soundcloud
        case "SiriusXM": self = .siriusXM
        case "Pandora": self = .pandora
        case "Plex": self = .plex
        case "Bandcamp": self = .bandcamp
        default: self = .unknown(rawValue)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    static func from(udn: String) -> SonosServiceType {
        // Extract the service ID from the UDN
        // Format: SA_RINCONXXXXX_X_#SvcXXXXX-...
        let components = udn.components(separatedBy: "_")
        guard components.count >= 2,
              let serviceId = components.last?.components(separatedBy: "-").first?.replacingOccurrences(of: "#Svc", with: "") else {
            return .unknown("Unknown")
        }
        
        switch serviceId {
        case "60423": return .pandora
        case "52231": return .appleMusic
        case "3079","2311": return .spotify
        case "44551": return .tidal
        case "85255": return .tunein
        case "40967": return .soundcloud
        case "9479": return .siriusXM
        case "54279": return .plex
        case "40199": return .bandcamp
        default: return .unknown(serviceId)
        }
    }
}

public struct MediaServer: Identifiable, Codable {
    public let id: String // UDN
    public let name: String // Nickname
    public let type: SonosServiceType
    public let token: String
    public let key: String
    public let serialNumber: Int
    public let flags: Int
    public let tier: Int
    
    public var serviceId: String {
        // Extract the service ID from the UDN
        let components = id.components(separatedBy: "_")
        guard components.count >= 2,
              let serviceId = components.last?.components(separatedBy: "-").first?.replacingOccurrences(of: "#Svc", with: "") else {
            return "Unknown"
        }
        return serviceId
    }
    
    init(udn: String, nickname: String, token: String, key: String, serialNum: Int, flags: Int, tier: Int) {
        self.id = udn
        self.name = nickname.isEmpty ? "Unknown" : nickname
        self.type = SonosServiceType.from(udn: udn)
        self.token = token
        self.key = key
        self.serialNumber = serialNum
        self.flags = flags
        self.tier = tier
    }
} 
