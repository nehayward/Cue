import Foundation

public struct SpotifyArtistAlbums: Decodable {
    public let href: String
    public let items: [AlbumItem]
    public let limit: Int
    public let next: String?
    public let offset: Int
    public let previous: String?
    public let total: Int

    public struct AlbumItem: Decodable, Identifiable {
        public let albumGroup: String
        public let albumType: String
        public let artists: [SpotifyArtistsInfo]?
        // Absent from market-aware responses (SpotifyAPI passes market=from_token).
        public let availableMarkets: [String]?
        public let externalUrls: ExternalUrls
        public let href: String
        public let id: String
        public let images: [SpotifyImage]
        public let name: String
        public let releaseDate: String
        public let releaseDatePrecision: String
        public let totalTracks: Int
        public let type: String
        public let uri: String
        
        public var releaseDateFormatted: String? {
            return releaseDate.components(separatedBy: "-").first
        }

//        public struct Artist: Codable {
//            let externalUrls: ExternalUrls
//            let href: String
//            let id: String
//            let name: String
//            let type: String
//            let uri: String
//        }
    }
}
