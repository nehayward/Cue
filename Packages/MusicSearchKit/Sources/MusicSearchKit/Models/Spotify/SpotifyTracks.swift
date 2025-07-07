import Foundation

public struct SpotifyTracks: Equatable, Decodable, Sendable {
    public let items: [SpotifyTrackItem]
}

public struct SpotifyTrackItem: Equatable, Decodable, Identifiable, Sendable {
    public let id: String?
    public let href: String?
    public let name: String
    public let album: SpotifyAlbumItem
    public let isPlayable: Bool?
    public let artists: [SpotifyArtistsInfo]
    public let externalUrls: ExternalUrls
    public let externalIds: SpotifyExternalIDS
    public let previewUrl: String?
    public let type: String
    public let uri: String
    public let explicit: Bool
    public let popularity: Int
    public let durationMs: Int
    public var allArtists: String { artists.compactMap { $0.name }.joined(separator: ", ") }
}
