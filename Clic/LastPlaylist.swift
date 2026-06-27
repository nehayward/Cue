import Foundation
import SonosKit
import Defaults
#if canImport(UIKit)
import UIKit
#endif

/// The most recently used playlist, persisted across the `lastPlaylist*` UserDefaults keys.
/// Centralizes reading and writing so call sites don't repeat the raw key access.
/// Main-actor isolated because adding/saving touch `@MainActor` services (MusicSearchService, UIMenuSystem).
@MainActor
struct LastPlaylist {
    let id: String
    let title: String
    let service: MusicService

    /// The last-used playlist, if one has been saved.
    static var current: LastPlaylist? {
        let defaults = UserDefaults.standard
        guard let id = defaults.string(forKey: AppStorageKeys.lastPlaylistID),
              let title = defaults.string(forKey: AppStorageKeys.lastPlaylistTitle) else {
            return nil
        }
        // Older builds only stored Sonos playlists, so a missing service means library.
        let raw = defaults.string(forKey: AppStorageKeys.lastPlaylistService) ?? "library"
        return LastPlaylist(id: id, title: title, service: MusicService(service: raw) ?? .library)
    }

    /// Adds `track` to this playlist via the appropriate service. Returns whether it succeeded.
    /// Streaming services dispatch through `MusicSearchService`; everything else goes to Sonos.
    @discardableResult
    func add(_ track: PlayableContent) async -> Bool {
        guard service != .library else {
            await SonosService.shared.addToPlaylist(playlistID: id, playableContent: track)
            return true
        }
        let playlist = PlayableContent(
            title: title,
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: service, id: id, type: .playlist, location: nil),
            metadata: nil
        )
        return await MusicSearchService.shared.addToServicePlaylist(track: track, playlist: playlist)
    }

    /// Playlist ids the user added to recently, most-recent first.
    static var recentIDs: [String] {
        UserDefaults.standard.stringArray(forKey: AppStorageKeys.recentPlaylistIDs) ?? []
    }

    private static let recentLimit = 12

    /// Persists `content` as the last-used playlist, records it in the recents list, and refreshes
    /// the Mac menu bar.
    static func save(_ content: PlayableContent) {
        let defaults = UserDefaults.standard
        defaults.set(content.id, forKey: AppStorageKeys.lastPlaylistID)
        defaults.set(content.title, forKey: AppStorageKeys.lastPlaylistTitle)
        defaults.set(content.content.service.sonosRawValue, forKey: AppStorageKeys.lastPlaylistService)

        // Move this playlist to the front of the recents list (dedup, capped).
        var recents = recentIDs.filter { $0 != content.id }
        recents.insert(content.id, at: 0)
        defaults.set(Array(recents.prefix(recentLimit)), forKey: AppStorageKeys.recentPlaylistIDs)

        #if targetEnvironment(macCatalyst)
        UIMenuSystem.main.setNeedsRebuild()
        #endif
    }
}
