import Foundation

/// Which playlist in the Music app is the one asked to be deleted, if Cue can
/// be sure of it (Cue (Mac) only: MusicKit can't delete a playlist, so
/// `ApplePlaylistDeleter` asks the Music app to). On its own so the rules that
/// keep the wrong playlist from going can be tested.
public enum ApplePlaylistDeletion {
    /// A playlist as the Music app lists it.
    public struct MusicPlaylist: Equatable, Sendable {
        /// `plain` is one someone made, the only kind that may go.
        public enum Kind: String, Equatable, Sendable {
            case plain, smart, genius, special, folder, subscription, other
        }

        public let name: String
        public let persistentID: String
        public let kind: Kind

        public init(name: String, persistentID: String, kind: Kind) {
            self.name = name
            self.persistentID = persistentID
            self.kind = kind
        }
    }

    public enum Refusal: Equatable, Sendable {
        /// Music has no such playlist: iCloud may not have brought it over.
        case notInMusic
        /// Music has this many playlists of that name.
        case sameName(count: Int)
        /// It isn't a playlist someone made.
        case wrongKind(MusicPlaylist.Kind)
        /// Music calls it something else: renamed elsewhere, or not synced.
        case nameDiffers(inMusic: String)
    }

    public enum Choice: Equatable, Sendable {
        /// MusicKit's own id says this is the playlist.
        case exact(persistentID: String)
        /// Found by its name alone, so it may go only if it has no songs,
        /// where a wrong guess has nothing to lose.
        case onlyIfEmpty(persistentID: String)
        case refuse(Refusal)
    }

    /// Picks from `playlists`, every playlist of any kind in Music's library.
    /// `linkedPersistentID` is what MusicKit says the playlist's id is in
    /// Music (`persistentID(fromMusicKitID:)`); MusicKit leaves out playlists
    /// with no songs, so those have none.
    ///
    /// Two of one name are refused even with a link: the name is all there is
    /// to check the link against, and a refusal costs little.
    public static func choose(
        name: String,
        linkedPersistentID: String?,
        in playlists: [MusicPlaylist]
    ) -> Choice {
        let sameName = playlists.filter { folded($0.name) == folded(name) }
        guard sameName.count < 2 else { return .refuse(.sameName(count: sameName.count)) }

        let found = linkedPersistentID.map { id in playlists.first { $0.persistentID == id } } ?? sameName.first
        guard let playlist = found else { return .refuse(.notInMusic) }
        guard playlist.name == name else { return .refuse(.nameDiffers(inMusic: playlist.name)) }
        guard playlist.kind == .plain else { return .refuse(.wrongKind(playlist.kind)) }

        return linkedPersistentID == nil
            ? .onlyIfEmpty(persistentID: playlist.persistentID)
            : .exact(persistentID: playlist.persistentID)
    }

    /// Music's `persistent ID` for an id from a MusicKit library read: the same
    /// 64 bits, signed and in decimal there, as 16 hex digits here. Nil for any
    /// other kind of id (a `p.…` is the web API's).
    public static func persistentID(fromMusicKitID id: String) -> String? {
        guard let value = Int64(id) else { return nil }
        let hex = String(UInt64(bitPattern: value), radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// Playlists that differ only by case or accent would be easy to mistake.
    private static func folded(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
