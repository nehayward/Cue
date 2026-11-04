import Foundation
import MusicKit
import MusicSearchKit
import OSLog
import SonosKit

/// Deleting an Apple Music playlist on the Mac. MusicKit and the Apple Music
/// API can't delete one, so this asks the Music app (`MusicLibraryScriptable`),
/// which is why there's no such thing on iPhone or iPad.
///
/// Only with Cue sure which playlist it is: Cue's playlists have `p.…` ids
/// (the web API's), Music's have persistent IDs, and MusicKit's library read
/// joins them (`ApplePlaylistDeletion`).
@MainActor
enum ApplePlaylistDeleter {
    /// Why not, in words for the listener.
    struct Problem: Error, Equatable {
        let message: String
        /// macOS's Automation permission is off: offer the way to it.
        var isPermission = false
    }

    private static let log = Logger(subsystem: "dance.cue", category: "playlists")
    static let automationSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// Whether an item's menu offers Delete at all: a playlist in the
    /// listener's Apple Music library, by its library id.
    static func offers(_ item: PlayableContent) -> Bool {
        item.content.service == .apple
            && item.content.type == .libraryPlaylist
            && item.content.id.hasPrefix("p.")
    }

    // MARK: - Before the confirmation

    /// What can be known without touching Music, so a playlist that can't go
    /// is told before Music opens or macOS asks: Apple's word that it's the
    /// listener's to change, and its persistent ID in Music as MusicKit has
    /// it. Returned for `delete`, nil when MusicKit has no link.
    static func check(_ item: PlayableContent) async throws -> String? {
        guard try await canEdit(item) else {
            throw Problem(message: "“\(item.title)” isn’t a playlist you made, so Cue leaves it alone. You can remove it in the Music app.")
        }
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(item.content.id))
        let linked = (try? await request.response().items) ?? []
        // MusicKit leaves out playlists with no songs.
        guard let playlist = linked.first else {
            log.info("no MusicKit link for \(item.content.id, privacy: .public)")
            return nil
        }
        guard linked.count == 1,
              let persistentID = ApplePlaylistDeletion.persistentID(fromMusicKitID: playlist.id.rawValue) else {
            throw Problem(message: "Cue can’t tell which playlist in Music this is. You can delete “\(item.title)” in the Music app.")
        }
        return persistentID
    }

    /// Apple's own answer. Unknown (offline, say) counts as no answer to act on.
    private static func canEdit(_ item: PlayableContent) async throws -> Bool {
        struct Response: Decodable {
            struct Row: Decodable {
                struct Attributes: Decodable {
                    let canEdit: Bool?
                }
                let attributes: Attributes
            }
            let data: [Row]
        }
        do {
            let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(item.content.id)")!
            let data = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response().data
            return try JSONDecoder().decode(Response.self, from: data).data.first?.attributes.canEdit == true
        } catch {
            log.error("couldn't read \(item.content.id, privacy: .public): \(error, privacy: .public)")
            throw Problem(message: "Cue couldn’t ask Apple Music about “\(item.title)”. Check your connection and try again.")
        }
    }

    // MARK: - Delete

    /// Asks Music again what it has, and deletes only what the rules pick.
    static func delete(_ item: PlayableContent, linkedPersistentID: String?) async throws {
        guard let music = MenuAppLaunchAtLoginManager.shared.bridge?.musicLibrary else {
            throw Problem(message: "Cue couldn’t reach the Music app. You can delete “\(item.title)” there.")
        }
        do {
            let playlists = try await music.playlists().map { row in
                ApplePlaylistDeletion.MusicPlaylist(
                    name: row["name"] ?? "",
                    persistentID: row["persistentID"] ?? "",
                    kind: row["kind"].flatMap(ApplePlaylistDeletion.MusicPlaylist.Kind.init) ?? .other
                )
            }
            let choice = ApplePlaylistDeletion.choose(name: item.title, linkedPersistentID: linkedPersistentID, in: playlists)
            log.info("\(item.content.id, privacy: .public) in \(playlists.count) of Music's playlists: \(String(describing: choice), privacy: .public)")
            switch choice {
            case let .refuse(refusal):
                throw Problem(message: message(for: refusal, title: item.title))
            case let .exact(persistentID):
                try await music.deletePlaylist(persistentID: persistentID, named: item.title)
            case let .onlyIfEmpty(persistentID):
                guard try await music.trackCount(ofPlaylist: persistentID) == 0 else {
                    throw Problem(message: "Cue can’t tell which playlist in Music this is. Try again in a minute, or delete “\(item.title)” in the Music app.")
                }
                try await music.deletePlaylist(persistentID: persistentID, named: item.title)
            }
        } catch let problem as Problem {
            throw problem
        } catch {
            let code = (error as NSError).code
            log.error("\(item.content.id, privacy: .public): \(error, privacy: .public)")
            throw problem(forEventError: code, title: item.title)
        }
    }

    private static func message(for refusal: ApplePlaylistDeletion.Refusal, title: String) -> String {
        switch refusal {
        case .notInMusic:
            "Music doesn’t have “\(title)”. If it was made just now, iCloud may still be bringing it over, so try again in a minute. If it stays, check that Sync Library is on in Music’s settings."
        case let .sameName(count):
            "Music has \(count) playlists called “\(title)”, so Cue won’t guess which to delete. Rename one in the Music app, or delete it there."
        case .wrongKind(.smart):
            "“\(title)” is a Smart Playlist in Music, so Cue leaves it alone. You can delete it in the Music app."
        case .wrongKind:
            "“\(title)” isn’t a playlist you made in Music, so Cue leaves it alone. You can remove it in the Music app."
        case let .nameDiffers(inMusic):
            "Music calls this playlist “\(inMusic)”, not “\(title)”, so Cue won’t delete it until the two agree. Try again in a minute."
        }
    }

    private static func problem(forEventError code: Int, title: String) -> Problem {
        // Apple event errors, whose names Catalyst's SDK doesn't have.
        switch code {
        case -1743, -1744: // errAEEventNotPermitted, errAEEventWouldRequireUserConsent
            Problem(
                message: "Cue isn’t allowed to control Music. Turn it on in System Settings ▸ Privacy & Security ▸ Automation, under Cue.",
                isPermission: true
            )
        case -1712: // errAETimeout
            Problem(message: "Music didn’t answer in time. Look in the Music app to see whether “\(title)” has gone.")
        case -600, -609: // procNotFound, connectionInvalid
            Problem(message: "Cue couldn’t open the Music app. You can delete “\(title)” there.")
        case -1728: // errAENoSuchObject
            Problem(message: "“\(title)” changed in Music just then, so Cue left it alone. Try again in a minute.")
        default:
            Problem(message: "Music wouldn’t do it (error \(code)). You can delete “\(title)” in the Music app.")
        }
    }

    // MARK: - After

    /// Takes the playlist off screen at once, then follows iCloud. The web API
    /// lists it for a while yet and `updateUsersApplePlaylists` only merges, so
    /// a read in that time puts it back in the list: it's taken out again until
    /// Apple Music says it's gone.
    static func finish(_ item: PlayableContent) {
        let browse = AppleMusicBrowseService.shared
        browse.userPlaylists.remove(item)
        leavePage(of: item)

        Task {
            for wait in [5, 10, 15, 30, 60] {
                try? await Task.sleep(for: .seconds(wait))
                let isGone = await isGone(item)
                browse.userPlaylists.remove(item)
                if isGone {
                    log.info("\(item.content.id, privacy: .public) gone from Apple Music")
                    await browse.updateUsersApplePlaylists(offset: 0)
                    return
                }
            }
            log.error("\(item.content.id, privacy: .public) still listed by Apple Music")
            AlertService.shared.showAlert(
                with: "“\(item.title)” has gone from Music, but Apple Music still lists it. Is Sync Library on?",
                imageName: "exclamationmark.triangle"
            )
        }
    }

    private static func isGone(_ item: PlayableContent) async -> Bool {
        let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(item.content.id)")!
        do {
            _ = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
            return false
        } catch let error as MusicDataRequest.Error {
            return error.status == 404
        } catch {
            return false
        }
    }

    /// Off its page, whether the sidebar opened it or a stack pushed it. The
    /// sheet's route is cleared first: gone with the page but left set, it
    /// would open again over the next playlist's page.
    private static func leavePage(of item: PlayableContent) {
        let window = LargeWindowState.shared
        window.currentRouter.presentedSheet = nil
        if window.isShowing(item) {
            window.select(AppState.shared.resolvedTab(Router.main.selectedTab))
        }
        let router = window.currentRouter
        let kept = router.path.filter { destination in
            guard case let .mediaDetail(content, _, _) = destination else { return true }
            return content.id != item.id
        }
        if kept.count != router.path.count {
            router.path = kept
        }
    }
}
