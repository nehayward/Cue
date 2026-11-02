import Foundation
import MusicSearchKit
import Observation
import WatchSync

/// The Plex, Subsonic and Audiobookshelf sign-ins the iPhone shared
/// (`WatchCredentials`), put where MusicSearchKit looks for them on this
/// watch — the Plex token and server in defaults, the Subsonic password and
/// the Audiobookshelf token in the keychain — so the watch browses and
/// downloads from the servers by itself. Each arrives with the iPhone's
/// context, and again when it changes there.
///
/// Audiobookshelf's is lent: an access token good for an hour, never the
/// refresh token, which the iPhone keeps (see
/// `WatchCredentials.Audiobookshelf`). When it's about to run out the
/// watch asks the iPhone for its next one (`renewTokenIfNeeded`).
@MainActor
@Observable
final class WatchAccounts {
    static let shared = WatchAccounts()

    /// What a new context changed, so the store does no more than it needs.
    enum Change {
        case none
        /// Only the Audiobookshelf token, renewed: what it turned away
        /// tries again.
        case tokenRenewed
        /// A sign-in or a server: what was looked up is looked up again.
        case signIns
    }

    private(set) var hasPlex: Bool
    private(set) var hasSubsonic: Bool
    private(set) var hasAudiobookshelf: Bool
    /// Whether the Plex server has books, as the iPhone last found.
    private(set) var plexHasBooks: Bool

    var hasMusic: Bool { hasPlex || hasSubsonic }
    /// Somewhere to browse books: Plex with books, or Audiobookshelf.
    var hasBooks: Bool { (hasPlex && plexHasBooks) || hasAudiobookshelf }

    /// How long before the Audiobookshelf token runs out a fresh one is
    /// asked for.
    static let tokenMargin: TimeInterval = 10 * 60
    private static let plexBooksKey = "plexHasBooks"

    private init() {
        hasPlex = Self.isPlexSet
        hasSubsonic = SubsonicAPI.shared.isConfigured
        hasAudiobookshelf = AudiobookshelfAPI.shared.isConfigured
        plexHasBooks = UserDefaults.standard.bool(forKey: Self.plexBooksKey)
    }

    /// Stores what changed, and only that: a new Subsonic password rotates
    /// the salt, and a new Plex server drops the connections found for the
    /// old one. A server or library the iPhone didn't send leaves the one
    /// here as it is.
    @discardableResult
    func apply(_ credentials: WatchCredentials) -> Change {
        let authenticator = PlexAuthenticator.shared
        let plex = PlexAPI.shared
        var changed = false
        var renewed = false
        if let shared = credentials.plex {
            var plexChanged = false
            if authenticator.authToken != shared.token {
                authenticator.authToken = shared.token
                plexChanged = true
            }
            if let serverID = shared.serverID, plex.serverID != serverID {
                plex.serverID = serverID
                plexChanged = true
            }
            if let section = shared.librarySectionID, plex.librarySelectionID != section {
                plex.librarySelectionID = section
                plexChanged = true
            }
            let preference = shared.connectionPreference.flatMap(PlexAPI.ConnectionPreference.init(rawValue:)) ?? .auto
            if plexChanged || plex.connectionPreference != preference {
                // Setting it drops the cached server and connections too.
                plex.connectionPreference = preference
                changed = true
            }
            // Which libraries hold books is the iPhone's choice (kept per
            // server, so after the server above).
            if plex.chosenAudiobookLibraryKeys != shared.bookLibraryKeys {
                plex.chosenAudiobookLibraryKeys = shared.bookLibraryKeys
            }
            let genreTagged = shared.includesGenreTaggedBooks ?? true
            if plex.includesGenreTaggedAudiobooks != genreTagged {
                plex.includesGenreTaggedAudiobooks = genreTagged
            }
            UserDefaults.standard.set(shared.hasBooks ?? false, forKey: Self.plexBooksKey)
        } else if authenticator.authToken != nil {
            authenticator.authToken = nil
            plex.serverID = nil
            plex.librarySelectionID = nil
            UserDefaults.standard.removeObject(forKey: Self.plexBooksKey)
            changed = true
        }

        let subsonic = SubsonicAPI.shared
        if let shared = credentials.subsonic {
            if subsonic.serverAddress != shared.serverAddress {
                subsonic.serverAddress = shared.serverAddress
                changed = true
            }
            if subsonic.username != shared.username {
                subsonic.username = shared.username
                changed = true
            }
            if subsonic.password != shared.password {
                subsonic.password = shared.password
                changed = true
            }
        } else if subsonic.isConfigured {
            subsonic.password = ""
            subsonic.username = ""
            subsonic.serverAddress = ""
            changed = true
        }

        let shelf = AudiobookshelfAPI.shared
        if let shared = credentials.audiobookshelf {
            let sameLogin = shelf.isConfigured && shelf.serverAddress == shared.serverAddress && shelf.username == shared.username
            if !sameLogin {
                shelf.adopt(address: shared.serverAddress, username: shared.username, accessToken: shared.accessToken)
                changed = true
            } else if AudiobookshelfAPI.currentAccessToken != shared.accessToken, Self.outlasts(shared.accessToken) {
                shelf.adopt(address: shared.serverAddress, username: shared.username, accessToken: shared.accessToken)
                renewed = true
            }
        } else if shelf.isConfigured {
            changed = true
            // With no refresh token here, signing out never asks the server.
            Task {
                await shelf.signOut()
                self.refresh()
            }
        }

        refresh()
        return changed ? .signIns : renewed ? .tokenRenewed : .none
    }

    /// Asks the iPhone for its sign-ins afresh when the Audiobookshelf token
    /// it lent runs out soon, or has: before books come down, or a shelf is
    /// read. Nothing to ask with no iPhone in reach; its next context
    /// brings one.
    func renewTokenIfNeeded() {
        guard hasAudiobookshelf, let expiry = AudiobookshelfAPI.accessTokenExpiry,
              expiry.timeIntervalSinceNow < Self.tokenMargin else { return }
        PhoneConnection.shared.requestCredentials()
    }

    /// Whether a token for the login held runs out later than the one held:
    /// an older context, read again as the session starts, mustn't put back
    /// a token the iPhone's answer has since replaced. One that can't be
    /// read either way is taken.
    private static func outlasts(_ token: String) -> Bool {
        guard let held = AudiobookshelfAPI.accessTokenExpiry,
              let offered = AudiobookshelfAPI.expiry(ofToken: token) else { return true }
        return offered > held
    }

    private func refresh() {
        hasPlex = Self.isPlexSet
        hasSubsonic = SubsonicAPI.shared.isConfigured
        hasAudiobookshelf = AudiobookshelfAPI.shared.isConfigured
        plexHasBooks = UserDefaults.standard.bool(forKey: Self.plexBooksKey)
    }

    /// Signed in, with a server: MusicSearchKit browses the one named.
    private static var isPlexSet: Bool {
        !(PlexAuthenticator.shared.authToken ?? "").isEmpty && PlexAPI.shared.serverID != nil
    }
}
