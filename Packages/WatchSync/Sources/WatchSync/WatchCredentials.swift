import Foundation

/// The iPhone's Plex and Subsonic sign-ins, shared so the watch can browse
/// and download from the servers on its own, with no iPhone in reach. They
/// travel in the iPhone's application context, and the watch stores them
/// where MusicSearchKit looks on any device: the Plex token and server in
/// defaults, the Subsonic password in the keychain.
public struct WatchCredentials: Codable, Equatable, Sendable {
    public struct Plex: Codable, Equatable, Sendable {
        public var token: String
        public var serverID: String?
        public var librarySectionID: String?
        public var connectionPreference: String?

        public init(token: String, serverID: String?, librarySectionID: String?, connectionPreference: String?) {
            self.token = token
            self.serverID = serverID
            self.librarySectionID = librarySectionID
            self.connectionPreference = connectionPreference
        }
    }

    public struct Subsonic: Codable, Equatable, Sendable {
        public var serverAddress: String
        public var username: String
        public var password: String

        public init(serverAddress: String, username: String, password: String) {
            self.serverAddress = serverAddress
            self.username = username
            self.password = password
        }
    }

    /// Nil when the iPhone isn't signed in to that service.
    public var plex: Plex?
    public var subsonic: Subsonic?

    public init(plex: Plex? = nil, subsonic: Subsonic? = nil) {
        self.plex = plex
        self.subsonic = subsonic
    }
}
