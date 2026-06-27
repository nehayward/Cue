import Foundation

public struct DeezerPlaylist: Codable {
    public let id: Int
    public let title: String
    public let picture: String?
    public let pictureMedium: String?
    public let pictureBig: String?
    public let pictureXl: String?
    /// The playlist owner. Deezer returns this under `creator` (not `user`).
    public let creator: DeezerUser?

    public var artworkURL: URL? {
        if let pictureXl, let url = URL(string: pictureXl) { return url }
        if let pictureBig, let url = URL(string: pictureBig) { return url }
        if let pictureMedium, let url = URL(string: pictureMedium) { return url }
        return picture.flatMap { URL(string: $0) }
    }
}
