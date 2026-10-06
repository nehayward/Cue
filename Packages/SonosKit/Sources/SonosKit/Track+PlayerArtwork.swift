import Foundation
import Nuke

public extension Track {
    /// The request the player's artwork view loads for this track.
    ///
    /// Built here rather than in the view so anything warming the cache ahead
    /// of the player — the skip prefetch, the Lock Screen artwork — lands in
    /// the exact entry the player reads. Nuke keys the cache on `imageID` and
    /// the thumbnail size, so a request that differed in either would load the
    /// same cover into an entry nothing ever looks at.
    var playerArtworkRequest: ImageRequest? {
        guard let url = artworkURL else { return nil }
        return .playerArtwork(url: url, imageID: playerArtworkCacheKey)
    }
}

public extension ImageRequest {
    static let playerArtworkSize: CGFloat = 500

    /// The now-playing cover at `pointSize`. At the default size this is
    /// `Track.playerArtworkRequest`; smaller artwork views (sidebar tiles)
    /// pass their own size and get their own, smaller cache entry.
    ///
    /// `thumbnail` rather than a `.resize` processor: ImageIO decodes straight
    /// to the target size, so a 3000 px cover never exists in memory as a
    /// full-size bitmap on its way to being shrunk.
    ///
    /// `imageID`, not `userInfo[.imageIdKey]`: Nuke 13 stopped reading that
    /// key — it survives only as a deprecated constant — and both the memory
    /// and data cache keys now come from `imageID`. Passing it via userInfo
    /// still compiles and silently does nothing, which split each cover into
    /// two entries (Sonos proxy URL, then service CDN URL).
    static func playerArtwork(url: URL, imageID: String, pointSize: CGFloat = playerArtworkSize) -> ImageRequest {
        var request = ImageRequest(url: url, priority: .high)
        request.imageID = imageID
        request.thumbnail = ThumbnailOptions(
            size: CGSize(width: pointSize, height: pointSize),
            unit: .points,
            contentMode: .aspectFit
        )
        return request
    }
}
