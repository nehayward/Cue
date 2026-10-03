import Foundation
import MusicKit

/// MusicKit's artwork for library rows whose cover is still a `musickit://`
/// URL after `unwrappingMusicKitArtwork` has done what it can, by the row's
/// content id.
///
/// The image pipeline's URL session can't open that scheme. On the iPhone
/// most library covers carry their path on Apple's artwork server, which
/// unwraps to `https`, but on the Mac most carry neither that nor a wrapped
/// `https` URL, and the Albums grid was a wall of placeholders. MusicKit's
/// own `ArtworkImage` draws any of them, so `ContentArtworkView` hands these
/// to it.
@MainActor
public enum MusicKitLibraryArtwork {
    private static var artworks: [String: Artwork] = [:]

    /// The artwork to draw with `ArtworkImage` in place of `url`, for the
    /// row with this content id. Nil when the image pipeline can load `url`
    /// itself.
    public static func artwork(for id: String, replacing url: URL?) -> Artwork? {
        guard !isLoadable(url) else { return nil }
        return artworks[id]
    }

    /// Keeps `artwork` for `row` when either of the row's cover URLs is one
    /// the image pipeline can't load.
    static func remember(_ artwork: Artwork?, for row: PlayableContent) {
        guard let artwork, !isLoadable(row.thumbnail) || !isLoadable(row.artwork) else { return }
        artworks[row.content.id] = artwork
    }

    private static func isLoadable(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return ["http", "https", "file"].contains(scheme)
    }
}
