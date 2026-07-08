import Foundation

public struct DeezerAlbum: Codable {
    public let id: Int
    public let title: String
    public let cover: String?
    public let coverMedium: String?
    public let coverBig: String?
    public let coverXl: String?
    public let artist: DeezerArtist?
    public let releaseDate: String?
    /// `nb_tracks` — distinguishes editions (standard vs deluxe) in rows.
    public let nbTracks: Int?

    public var releaseYear: String? {
        releaseDate.flatMap { $0.split(separator: "-").first.map(String.init) }
    }

    public var artworkURL: URL? {
        if let coverXl, let url = URL(string: coverXl) { return url }
        if let coverBig, let url = URL(string: coverBig) { return url }
        if let coverMedium, let url = URL(string: coverMedium) { return url }
        return cover.flatMap { URL(string: $0) }
    }
}
