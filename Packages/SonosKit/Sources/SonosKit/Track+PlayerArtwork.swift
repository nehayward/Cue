import Foundation
import Nuke

public extension Track {
    /// The request the player's artwork view loads for this track.
    ///
    /// Built here rather than in the view so anything warming the cache ahead
    /// of the player — the skip prefetch — lands in the exact entry the player
    /// reads. Nuke keys the cache on `imageID` and the processors, so a request
    /// that differed in either would load the same cover into an entry nothing
    /// ever looks at.
    var playerArtworkRequest: ImageRequest? {
        guard let url = artworkURL else { return nil }
        var request = ImageRequest(
            url: url,
            processors: [.resize(width: 500)],
            priority: .high
        )
        // `imageID`, not `userInfo[.imageIdKey]`: Nuke 13 stopped reading that
        // key — it survives only as a deprecated constant — and both the memory
        // and data cache keys now come from `imageID`. Passing it via userInfo
        // still compiles and silently does nothing, which split each cover into
        // two entries (Sonos proxy URL, then service CDN URL).
        request.imageID = playerArtworkCacheKey
        return request
    }
}
