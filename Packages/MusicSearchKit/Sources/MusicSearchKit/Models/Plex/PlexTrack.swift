import Foundation

public struct PlexTrack {
    public var title: String
    public var artist: String
    public var duration: Int
    public var audioChannels: Int
    public var audioCodec: String
    public var container: String
    public var file: String
    public var parentThumbnail: String
    public var ratingKey: String // Used to play on Sonos
    public var imageURL: URL?
    public var id: String
}
