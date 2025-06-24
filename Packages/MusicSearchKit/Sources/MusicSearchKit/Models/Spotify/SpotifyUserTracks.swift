import Foundation

public struct SpotifyUserTracksResponse: Decodable {
    public let href: String?
    public let items: [SpotifyUserTrack?]
    public let limit: Int
    public let next: String?
    public let offset: Int
    public let previous: String?
    public let total: Int
}

public struct SpotifyUserTrack: Decodable {
    public let track: SpotifyTrackItem
    public let addedAt: Date?
}
