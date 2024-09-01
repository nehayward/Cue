
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
    public let mediaMetadata: TidalMediaMetadata?
    
    public var isExplicit: Bool {
        properties?.content?.contains("explicit") ?? false
    }
    
    public var releaseDateFormatted: String? {
        if let releaseDate {
            return releaseDate.components(separatedBy: "-").first
        }
        return nil
    }
}
