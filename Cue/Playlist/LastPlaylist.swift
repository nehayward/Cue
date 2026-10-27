import Foundation
import SonosKit
import Defaults
import SwiftUI
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

    /// A lightweight `PlayableContent` for this playlist (id / title / service) — enough to open its
    /// detail screen or dispatch a service add.
    var playableContent: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: service, id: id, type: .playlist, location: nil),
            metadata: nil
        )
    }

    /// Adds `track` to this playlist via the appropriate service. Returns whether it succeeded.
    /// Streaming services dispatch through `MusicSearchService`; everything else goes to Sonos.
    @discardableResult
    func add(_ track: PlayableContent) async -> Bool {
        guard service != .library else {
            await SonosService.shared.addToPlaylist(playlistID: id, playableContent: track)
            return true
        }
        return await MusicSearchService.shared.addToServicePlaylist(track: track, playlist: playableContent)
    }

    /// Whether `item` can go in this playlist. A Sonos playlist takes
    /// anything a speaker can play; a streaming playlist only tracks from its
    /// own service (never albums, which the song-add endpoints can't handle).
    func accepts(_ item: PlayableContent) -> Bool {
        // A Sonos playlist can't hold a file from this device, and can't be
        // reached at all while Sonos is switched off or the phone is on
        // cellular.
        if service == .library {
            return SonosService.shared.isAvailable && !item.content.service.playsOnDeviceOnly
        }
        return service == item.content.service && [.track, .libraryTrack].contains(item.content.type)
    }

    /// Adds `item` and says how it went: a toast that opens the playlist when
    /// tapped, or one saying it couldn't be added.
    func addAndAnnounce(_ item: PlayableContent) async {
        let alertService = AlertService.shared
        guard await add(item) else {
            alertService.showAlert(with: "Couldn’t add to \(title)", imageName: "exclamationmark.triangle")
            return
        }
        alertService.showAlertContent(with: item, subtitle: "Added to \(title)", symbolName: "plus")

        // Let tapping the toast open the playlist. For Sonos, resolve the real playlist so the
        // detail carries artwork; streaming playlists open from a lightweight stub (the detail
        // view loads them by id).
        let target: PlayableContent?
        if service == .library {
            target = await SonosService.shared.sonosPlaylists().first(where: { $0.id == id })
        } else {
            target = playableContent
        }
        if let target {
            alertService.alert.handleTap = {
                MediaDetailPresenter.present(target)
            }
        }
    }

    /// Recently-added playlist keys, most-recent first. Each key is namespaced by service
    /// (`"<service>:<id>"`) so a Sonos and a streaming playlist that share a raw id stay distinct.
    static var recentKeys: [String] {
        UserDefaults.standard.stringArray(forKey: AppStorageKeys.recentPlaylistIDs) ?? []
    }

    /// The recents key for a playlist: its service paired with its raw id.
    static func recentKey(for content: PlayableContent) -> String {
        "\(content.content.service.sonosRawValue):\(content.id)"
    }

    private static let recentLimit = 12

    /// Persists `content` as the last-used playlist, records it in the recents list, and refreshes
    /// the menu bar (the Mac's, and iPad's), whose Add to Last Playlist is named for it.
    static func save(_ content: PlayableContent) {
        let defaults = UserDefaults.standard
        defaults.set(content.id, forKey: AppStorageKeys.lastPlaylistID)
        defaults.set(content.title, forKey: AppStorageKeys.lastPlaylistTitle)
        defaults.set(content.content.service.sonosRawValue, forKey: AppStorageKeys.lastPlaylistService)

        // Move this playlist to the front of the recents list (dedup, capped).
        let key = recentKey(for: content)
        var recents = recentKeys.filter { $0 != key }
        recents.insert(key, at: 0)
        defaults.set(Array(recents.prefix(recentLimit)), forKey: AppStorageKeys.recentPlaylistIDs)

        #if canImport(UIKit)
        UIMenuSystem.main.setNeedsRebuild()
        #endif
    }
}
