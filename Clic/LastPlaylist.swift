import Foundation
import SonosKit
import Defaults
#if canImport(UIKit)
import UIKit
#endif

/// The most recently used playlist, persisted across the `lastPlaylist*` UserDefaults keys.
/// Centralizes reading and writing so call sites don't repeat the raw key access.
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

    /// Persists `content` as the last-used playlist and refreshes the Mac menu bar.
    static func save(_ content: PlayableContent) {
        let defaults = UserDefaults.standard
        defaults.set(content.id, forKey: AppStorageKeys.lastPlaylistID)
        defaults.set(content.title, forKey: AppStorageKeys.lastPlaylistTitle)
        defaults.set(content.content.service.sonosRawValue, forKey: AppStorageKeys.lastPlaylistService)
        #if targetEnvironment(macCatalyst)
        UIMenuSystem.main.setNeedsRebuild()
        #endif
    }
}
