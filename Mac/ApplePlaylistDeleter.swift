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

    /// What `check` learned, for `delete`: its persistent ID in Music as MusicKit
    /// has it, nil when MusicKit has no link.
    struct Checked: Equatable {
        fileprivate let persistentID: String?
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
    /// listener's to change, and MusicKit's link to it in Music.
    static func check(_ item: PlayableContent) async throws(Problem) -> Checked {
        guard try await canEdit(item) else {
            throw Problem(message: "“\(item.title)” isn’t a playlist you made, so Cue leaves it alone. You can remove it in the Music app.")
        }
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(item.content.id))
        let linked = (try? await request.response().items) ?? []
        // MusicKit leaves out playlists with no songs.
        guard let playlist = linked.first else {
            log.info("no MusicKit link for \(item.content.id, privacy: .public)")
            return Checked(persistentID: nil)
        }
        guard linked.count == 1,
              let persistentID = ApplePlaylistDeletion.persistentID(fromMusicKitID: playlist.id.rawValue) else {
            throw Problem(message: "Cue can’t tell which playlist in Music this is. You can delete “\(item.title)” in the Music app.")
        }
        return Checked(persistentID: persistentID)
    }

    /// Apple's own answer. Unknown (offline, say) counts as no answer to act on.
    private static func canEdit(_ item: PlayableContent) async throws(Problem) -> Bool {
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
            let data = try await libraryRequest(for: item).response().data
            return try JSONDecoder().decode(Response.self, from: data).data.first?.attributes.canEdit == true
        } catch {
            log.error("couldn't read \(item.content.id, privacy: .public): \(error, privacy: .public)")
            throw Problem(message: "Cue couldn’t ask Apple Music about “\(item.title)”. Check your connection and try again.")
        }
    }

    private static func libraryRequest(for item: PlayableContent) -> MusicDataRequest {
        let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(item.content.id)")!
        return MusicDataRequest(urlRequest: URLRequest(url: url))
    }

    // MARK: - Delete

    /// Asks Music again what it has, deletes only what the rules pick, and takes
    /// the playlist out of Cue's list.
    static func delete(_ item: PlayableContent, _ checked: Checked) async throws(Problem) {
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
            let choice = ApplePlaylistDeletion.choose(name: item.title, linkedPersistentID: checked.persistentID, in: playlists)
            log.info("\(item.content.id, privacy: .public) in \(playlists.count) of Music's playlists: \(String(describing: choice), privacy: .public)")
            let persistentID: String
            switch choice {
            case let .refuse(refusal):
                throw Problem(message: message(for: refusal, title: item.title))
            case let .exact(id):
                persistentID = id
            case let .onlyIfEmpty(id):
                guard try await music.trackCount(ofPlaylist: id) == 0 else {
                    throw Problem(message: "Cue can’t tell which playlist in Music this is. Try again in a minute, or delete “\(item.title)” in the Music app.")
                }
                persistentID = id
            }
            try await music.deletePlaylist(persistentID: persistentID, named: item.title)
        } catch let problem as Problem {
            throw problem
        } catch {
            let code = (error as NSError).code
            log.error("\(item.content.id, privacy: .public): \(error, privacy: .public)")
            throw problem(forEventError: code, title: item.title)
        }
        removeFromList(item)
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

    /// Takes the playlist out of the list at once, then follows iCloud. The web
    /// API lists it for a while yet and `updateUsersApplePlaylists` only merges,
    /// so a read in that time puts it back in the list: it's taken out again until
    /// Apple Music says it's gone.
    private static func removeFromList(_ item: PlayableContent) {
        let browse = AppleMusicBrowseService.shared
        browse.userPlaylists.remove(item)

        Task {
            for wait in [5, 10, 15, 30, 60] {
                try? await Task.sleep(for: .seconds(wait))
                let isGone = await isGone(item)
                if browse.userPlaylists.contains(item) {
                    browse.userPlaylists.remove(item)
                }
                if isGone {
                    log.info("\(item.content.id, privacy: .public) gone from Apple Music")
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
        do {
            _ = try await libraryRequest(for: item).response()
            return false
        } catch let error as MusicDataRequest.Error {
            return error.status == 404
        } catch {
            return false
        }
    }
}
