import Foundation

public struct TrackEvent {
    public let info: SocketInfo
    public let metadata: MetadataStatusResponse?

    // Decode from the array format
    static func decode(from data: Data) throws -> Self? {
        // Decode as an array of generic JSON objects
        let decoder = JSONDecoder()
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        var info: SocketInfo?
        var state: MetadataStatusResponse?

        for item in array {
            // Try decoding info
            if info == nil, let infoData = try? JSONSerialization.data(withJSONObject: item),
               let i = try? decoder.decode(SocketInfo.self, from: infoData) {
                info = i
                if info?.type != "metadataStatus" { return nil }
                continue
            }

            // Try decoding state
            if state == nil, let stateData = try? JSONSerialization.data(withJSONObject: item),
               let s = try? decoder.decode(MetadataStatusResponse.self, from: stateData),
               s.objectType != "" {
                state = s
                continue
            }
        }

        guard let socketInfo = info else {
            throw NSError(domain: "PlaybackEvent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing SocketInfo"])
        }

        return Self(info: socketInfo, metadata: state)
    }
}


public struct MetadataStatusResponse: Codable {
    public let currentItem: QueueItem?
    public let nextItem: QueueItem?
    public let container: SonosContainer?
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case currentItem
        case nextItem
        case container
        case objectType = "_objectType"
    }
}

// MARK: - QueueItem
public struct QueueItem: Codable {
    public let track: SonosTrackInfo?
    public let policies: PlaybackPolicy?
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case track
        case policies
        case objectType = "_objectType"
    }
}

// MARK: - Track
public struct SonosTrackInfo: Codable {
    public let images: [TrackEventImage]?
    public let artist: SonosArtist?
    public let service: SonosServiceInfo?
    public let id: UniversalMusicObjectId?
    public let durationMillis: Int?
    public let imageUrl: String?
    public let album: SonosAlbum?
    public let type: String?
    public let objectType: String?
    public let name: String?
    public let quality: SonosTrackQuality?

    enum CodingKeys: String, CodingKey {
        case images, artist, service, id, album, type, name, quality
        case durationMillis, imageUrl
        case objectType = "_objectType"
    }
}

// MARK: - Supporting Types
public struct TrackEventImage: Codable {
    public let url: String?
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case url
        case objectType = "_objectType"
    }
}

public struct SonosArtist: Codable {
    public let name: String?
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case objectType = "_objectType"
    }
}

public struct SonosServiceInfo: Codable {
    public let id: String?
    public let name: String?
    public let images: [TrackEventImage]?
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case id, name, images
        case objectType = "_objectType"
    }
}

public struct UniversalMusicObjectId: Codable {
    public let accountId: String?
    public let serviceId: String?
    public let objectId: String?
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case accountId, serviceId, objectId
        case objectType = "_objectType"
    }
}

public struct SonosAlbum: Codable {
    public let name: String?
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case objectType = "_objectType"
    }
}

public struct SonosTrackQuality: Codable, Hashable {
    public let bitDepth: Int?
    public let lossless: Bool?
    public let immersive: Bool?
    public let sampleRate: Int?
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case bitDepth, lossless, immersive, sampleRate
        case objectType = "_objectType"
    }

    /// For a quality the app worked out itself — what this device's own
    /// player is decoding — rather than one a speaker reported.
    public init(bitDepth: Int? = nil, lossless: Bool? = nil, immersive: Bool? = nil, sampleRate: Int? = nil, objectType: String? = nil) {
        self.bitDepth = bitDepth
        self.lossless = lossless
        self.immersive = immersive
        self.sampleRate = sampleRate
        self.objectType = objectType
    }

    public var sampleRateFormatted: String {
        guard let sampleRate = sampleRate else { return "" }
        let rateInKHz = Double(sampleRate) / 1000.0
        if rateInKHz.truncatingRemainder(dividingBy: 1) == 0 {
            // No decimal point needed
            return "\(Int(rateInKHz)) kHz"
        } else {
            // Keep 1 decimal place if needed (e.g. 44.1 kHz)
            return String(format: "%.1f kHz", rateInKHz)
        }
    }
}

public struct PlaybackPolicy: Codable {
    public let objectType: String?

    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
    }
}

public struct SonosContainer: Codable {
    public let images: [TrackEventImage]?
    public let objectType: String?
    public let service: SonosServiceInfo?
    public let htInputFormat: HTInputFormat?
    public let type: String?
    public let name: String?
    public let id: UniversalMusicObjectId?
    
    public struct HTInputFormat: Codable {
        public let numLFEChannels: Int?
        public let numGroundChannels: Int?
        public let numHeightChannels: Int?
        public let streamDescription: String?
        public let objectType: String?
        
        enum CodingKeys: String, CodingKey {
            case numLFEChannels
            case numGroundChannels
            case numHeightChannels
            case streamDescription
            case objectType = "_objectType"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case images
        case objectType = "_objectType"
        case htInputFormat
        case service
        case type
        case name
        case id
    }
}

