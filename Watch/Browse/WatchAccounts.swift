import Foundation
import MusicSearchKit
import Observation
import WatchSync

/// The Plex and Subsonic sign-ins the iPhone shared (`WatchCredentials`),
/// put where MusicSearchKit looks for them on this watch — the Plex token
/// and server in defaults, the Subsonic password in the keychain — so the
/// watch browses and downloads from the servers by itself. Each arrives
/// with the iPhone's context, and again when it changes there.
@MainActor
@Observable
final class WatchAccounts {
    static let shared = WatchAccounts()

    private(set) var hasPlex: Bool
    private(set) var hasSubsonic: Bool

    var hasAny: Bool { hasPlex || hasSubsonic }

    private init() {
        hasPlex = Self.isPlexSet
        hasSubsonic = SubsonicAPI.shared.isConfigured
    }

    /// Stores what changed, and only that: a new Subsonic password rotates
    /// the salt, and a new Plex server drops the connections found for the
    /// old one. A server or library the iPhone didn't send leaves the one
    /// here as it is. True when anything changed, so what was looked up
    /// with the old sign-ins is looked up again.
    @discardableResult
    func apply(_ credentials: WatchCredentials) -> Bool {
        let authenticator = PlexAuthenticator.shared
        let plex = PlexAPI.shared
        var changed = false
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
        } else if authenticator.authToken != nil {
            authenticator.authToken = nil
            plex.serverID = nil
            plex.librarySelectionID = nil
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

        refresh()
        return changed
    }

    private func refresh() {
        hasPlex = Self.isPlexSet
        hasSubsonic = SubsonicAPI.shared.isConfigured
    }

    /// Signed in, with a server: MusicSearchKit browses the one named.
    private static var isPlexSet: Bool {
        !(PlexAuthenticator.shared.authToken ?? "").isEmpty && PlexAPI.shared.serverID != nil
    }
}
