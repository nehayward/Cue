import Foundation

public struct PlayableContentMetadata: Equatable, Codable, Hashable {
    public let duration: Duration?
    public let popularity: Int?
    public let artist: String?
    public let artistID: String?
    public let album: String?
    public let albumID: String?
    public let isrc: String?
    public var position: Int?
    public var plexRatingKey: String?
    public var URIMetadata: String?
    public var radioStation: Bool?

    init(
        duration: Duration? = nil,
        popularity: Int? = nil,
        artist: String? = nil,
        artistID: String? = nil,
        album: String? = nil,
        albumID: String? = nil,
        isrc: String? = nil,
        position: Int? = nil,
        plexRatingKey: String? = nil,
        URIMetadata: String? = nil,
        radioStation: Bool? = nil
    ) {
        self.duration = duration
        self.popularity = popularity
        self.artist = artist
        self.artistID = artistID
        self.album = album
        self.albumID = albumID
        self.isrc = isrc
        self.position = position
        self.plexRatingKey = plexRatingKey
        self.URIMetadata = URIMetadata
        self.radioStation = radioStation
    }
}
