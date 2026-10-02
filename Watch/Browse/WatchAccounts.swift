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
    /// old one.
    func apply(_ credentials: WatchCredentials) {
        let authenticator = PlexAuthenticator.shared
        let plex = PlexAPI.shared
        if let shared = credentials.plex {
            var changed = false
            if authenticator.authToken != shared.token {
                authenticator.authToken = shared.token
                changed = true
            }
            if plex.serverID != shared.serverID {
                plex.serverID = shared.serverID
                changed = true
            }
            if plex.librarySelectionID != shared.librarySectionID {
                plex.librarySelectionID = shared.librarySectionID
                changed = true
            }
            let preference = shared.connectionPreference.flatMap(PlexAPI.ConnectionPreference.init(rawValue:)) ?? .auto
            if changed || plex.connectionPreference != preference {
                // Setting it drops the cached server and connections too.
                plex.connectionPreference = preference
            }
        } else if authenticator.authToken != nil {
            authenticator.authToken = nil
            plex.serverID = nil
            plex.librarySelectionID = nil
        }

        let subsonic = SubsonicAPI.shared
        if let shared = credentials.subsonic {
            if subsonic.serverAddress != shared.serverAddress {
                subsonic.serverAddress = shared.serverAddress
            }
            if subsonic.username != shared.username {
                subsonic.username = shared.username
            }
            if subsonic.password != shared.password {
                subsonic.password = shared.password
            }
        } else if subsonic.isConfigured {
            subsonic.password = ""
            subsonic.username = ""
            subsonic.serverAddress = ""
        }

        hasPlex = Self.isPlexSet
        hasSubsonic = subsonic.isConfigured
    }

    private static var isPlexSet: Bool {
        PlexAuthenticator.shared.authToken != nil && PlexAPI.shared.serverID != nil
    }
}
