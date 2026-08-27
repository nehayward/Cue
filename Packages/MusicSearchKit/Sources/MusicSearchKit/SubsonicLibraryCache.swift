import Foundation

/// The Subsonic song library on disk. See `LibraryCache` for how it is kept
/// and when it is trusted; the identity here is the server plus the login,
/// since the same address with a different user is a different library.
extension SubsonicAPI {
    private static let libraryCache = LibraryCache<SubsonicSong>(name: "SubsonicLibrary")

    private var cacheOwner: String { "\(serverAddress)|\(username)" }

    public func cachedSongLibrary() async -> [SubsonicSong]? {
        await Self.libraryCache.load(owner: cacheOwner)
    }

    public func cacheSongLibrary(_ songs: [SubsonicSong]) {
        Self.libraryCache.save(songs, owner: cacheOwner)
    }

    public var cachedSongLibrarySize: Int { Self.libraryCache.sizeInBytes }

    /// Removes the saved library — on disconnect (it is the user's own library
    /// metadata, and the server it came from is gone) and whenever a refresh
    /// should really re-read the server.
    public func clearCachedSongLibrary() {
        Self.libraryCache.clear()
    }
}
