import Foundation

public class PlayableContentMetadata: Equatable, Codable, Hashable {
    // Properties
    public let duration: Duration?
    public let popularity: Int?
    public let artist: String?
    public let artistID: String?
    public let album: String?
    public let albumID: String?
    public let albumYear: Date?
    public let isrc: String?
    public var position: Int?
    public var audioCodec: String?
    public var URIMetadata: String?
    public var radioStation: Bool?
    public var isPlayable: Bool? // A song might not be released so it's not playable.
    public var isExplicit: Bool?
    public var isSingle: Bool?

    // Initializer
    public init(
        duration: Duration? = nil,
        popularity: Int? = nil,
        artist: String? = nil,
        artistID: String? = nil,
        album: String? = nil,
        albumID: String? = nil,
        albumYear: Date? = nil,
        isrc: String? = nil,
        position: Int? = nil,
        audioCodec: String? = nil,
        URIMetadata: String? = nil,
        radioStation: Bool? = nil,
        isPlayable: Bool? = true,
        isExplicit: Bool? = false,
        isSingle: Bool? = false
    ) {
        self.duration = duration
        self.popularity = popularity
        self.artist = artist
        self.artistID = artistID
        self.album = album
        self.albumID = albumID
        self.albumYear = albumYear
        self.isrc = isrc
        self.position = position
        self.audioCodec = audioCodec
        self.URIMetadata = URIMetadata
        self.radioStation = radioStation
        self.isPlayable = isPlayable
        self.isExplicit = isExplicit
        self.isSingle = isSingle
    }

    // Equatable conformance
    public static func == (lhs: PlayableContentMetadata, rhs: PlayableContentMetadata) -> Bool {
        lhs.duration == rhs.duration &&
        lhs.popularity == rhs.popularity &&
        lhs.artist == rhs.artist &&
        lhs.artistID == rhs.artistID &&
        lhs.album == rhs.album &&
        lhs.albumID == rhs.albumID &&
        lhs.albumYear == rhs.albumYear &&
        lhs.isrc == rhs.isrc &&
        lhs.position == rhs.position &&
        lhs.audioCodec == rhs.audioCodec &&
        lhs.URIMetadata == rhs.URIMetadata &&
        lhs.radioStation == rhs.radioStation &&
        lhs.isPlayable == rhs.isPlayable &&
        lhs.isExplicit == rhs.isExplicit &&
        lhs.isSingle == rhs.isSingle
    }

    // Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(duration)
        hasher.combine(popularity)
        hasher.combine(artist)
        hasher.combine(artistID)
        hasher.combine(album)
        hasher.combine(albumID)
        hasher.combine(albumYear)
        hasher.combine(isrc)
        hasher.combine(position)
        hasher.combine(audioCodec)
        hasher.combine(URIMetadata)
        hasher.combine(radioStation)
        hasher.combine(isPlayable)
        hasher.combine(isExplicit)
        hasher.combine(isSingle)
    }
}
