import Foundation

public struct PlexTrack {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Int?
    public var audioChannels: Int?
    public var audioCodec: String?
    /// Media bitrate in kbps; distinguishes duplicate editions of a track
    /// (the same album ripped at different qualities) in search results.
    public var bitrate: Int?
    public var container: String?
    public var file: String?
    public var parentThumbnail: String?
    public var ratingKey: String // Used to play on Sonos
    public var parentRatingKey: String? // Album Key
    public var grandparentRatingKey: String? // Artist
    public var imageURL: URL?
    public var id: String
    public var librarySectionID: Int?
    /// Plex star rating 0-10 (10 = loved); drives the heart in search rows.
    public var userRating: Double? = nil
}
