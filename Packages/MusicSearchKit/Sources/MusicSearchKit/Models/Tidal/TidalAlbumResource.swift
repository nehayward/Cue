
public struct TidalAlbumResource: Codable {
    public let id: String
    public let barcodeId: String?
    public let title: String
    public let artists: [TidalArtistResource]
    public let duration: Int
    public let releaseDate: String?
    public let imageCover: [TidalImage]?
    public let numberOfVolumes: Int?
    public let numberOfTracks: Int?
    public let numberOfVideos: Int?
    public let copyright: String?
    public let tidalUrl: String
    public let properties: TidalProperties?
    public let mediaMetadata: [String]?
    public let isExplicit: Bool
    public let popularity: Double
    /// Tidal's release type: "ALBUM", "EP" or "SINGLE".
    public var albumType: String? = nil

    /// Singles and EPs, as opposed to full albums.
    public var isSingleOrEP: Bool {
        albumType == "SINGLE" || albumType == "EP"
    }
    
    public var releaseDateFormatted: String? {
        if let releaseDate {
            return releaseDate.components(separatedBy: "-").first
        }
        return nil
    }
    
    public var dolbyAtmos: String? {
        if mediaMetadata?.contains(where: { $0.caseInsensitiveCompare("dolby_atmos") == .orderedSame }) ?? false {
            return "Dolby Atmos"
        }
        return nil
    }
    
    public var lossless: String? {
        if mediaMetadata?.contains(where: { $0.caseInsensitiveCompare("LOSSLESS") == .orderedSame }) ?? false {
            return "Lossless"
        }
        return nil
    }
}
