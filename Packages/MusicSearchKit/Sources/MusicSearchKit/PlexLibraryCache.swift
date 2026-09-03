import Foundation

/// The Plex song library on disk. Same store and rules as Subsonic's — see
/// `LibraryCache`. The identity is the server plus the music section, since
/// pointing Cue at a different library is a different library.
///
/// Saved songs carry no stream or artwork URLs: those embed the Plex token,
/// which rotates, so they are rebuilt with `decorated(_:)` on the way back in
/// rather than written to disk.
extension PlexAPI {
    private static let libraryCache = LibraryCache<PlexMetadata>(name: "PlexLibrary")

    private var cacheOwner: String { "\(serverID ?? "")|\(librarySelectionID ?? "")" }

    public func cachedSongLibrary() async -> [PlexMetadata]? {
        guard let songs = await Self.libraryCache.load(owner: cacheOwner) else { return nil }
        return await decorated(songs)
    }

    public func cacheSongLibrary(_ songs: [PlexMetadata]) {
        Self.libraryCache.save(songs, owner: cacheOwner)
    }

    public var cachedSongLibrarySize: Int { Self.libraryCache.sizeInBytes }

    public func clearCachedSongLibrary() {
        Self.libraryCache.clear()
    }
}
