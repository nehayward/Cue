import Foundation
import Nuke

extension ImageRequest {
    /// A speaker gives each track its own artwork address, so covers are kept
    /// by album: the next song on the same album shows at once. A track with
    /// no album (radio) is kept by its address.
    static func cover(_ url: URL?, album: String) -> ImageRequest? {
        guard let url else { return nil }
        var request = ImageRequest(url: url)
        if !album.isEmpty {
            request.imageID = album
        }
        return request
    }
}
