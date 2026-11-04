import Foundation

/// The Music app's library, asked by Apple events, which only this bundle can
/// send. MusicKit can't delete a playlist (`ApplePlaylistDeleter`). Errors are
/// `NSOSStatusErrorDomain`'s with the Apple event's code. Each call opens Music
/// in the background if it's closed; the first may wait on macOS's Automation
/// prompt.
@objc(MusicLibraryScriptable)
protocol MusicLibraryScriptable: NSObjectProtocol {
    /// Every playlist in Music's library, of any kind: `name`, `persistentID`
    /// and `kind` (an `ApplePlaylistDeletion.MusicPlaylist.Kind`'s raw value).
    func playlists() async throws -> [[String: String]]

    /// How many songs the user playlist has.
    func trackCount(ofPlaylist persistentID: String) async throws -> Int

    /// Deletes the user playlist, once Music has said again that it goes by
    /// `name`. Returns only once Music no longer has it.
    func deletePlaylist(persistentID: String, named name: String) async throws
}
