import Foundation

public struct PlexAlbum {
    public var title: String
    public var artist: String
    public var year: String
    public var thumb: String?
    public var art: String
    public var ratingKey: String // Used to play on Sonos
    public var parentRatingKey: String? // Artist Key
    public var imageURL: URL?
    public var id: String
    public var librarySectionID: Int?
    /// Plex star rating 0-10 (10 = loved); drives the heart in search rows.
    public var userRating: Double? = nil
    /// Number of tracks; distinguishes editions of the same album
    /// (standard vs deluxe) in search rows.
    public var leafCount: Int? = nil
}
