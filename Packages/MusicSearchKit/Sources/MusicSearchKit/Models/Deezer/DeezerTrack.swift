import Foundation

public struct DeezerTrack: Codable {
    public let id: Int
    public let title: String
    public let duration: Int?
    public let preview: String?
    public let artist: DeezerArtist?
    public let album: DeezerAlbum?

    public var previewURL: URL? {
        preview.flatMap { URL(string: $0) }
    }
}
