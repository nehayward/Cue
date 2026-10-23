import Foundation

/// The iPhone's Plex, Subsonic and Audiobookshelf sign-ins, shared so the
/// watch can browse and download from the servers on its own, with no
/// iPhone in reach. They travel in the iPhone's application context, and
/// the watch stores them where MusicSearchKit looks on any device: the Plex
/// token and server in defaults, the Subsonic password and the
/// Audiobookshelf token in the keychain.
public struct WatchCredentials: Codable, Equatable, Sendable {
    public struct Plex: Codable, Equatable, Sendable {
        public var token: String
        public var serverID: String?
        public var librarySectionID: String?
        public var connectionPreference: String?
        /// Whether the server has books, as the iPhone last found: the
        /// watch lists Plex under Audiobooks while it does.
        public var hasBooks: Bool?
        /// The libraries chosen as books on the iPhone, or nil while none
        /// were (then those that look kept for books are).
        public var bookLibraryKeys: [String]?
        /// Whether albums under an audiobook genre in the music library are
        /// books too; nil for the default, on.
        public var includesGenreTaggedBooks: Bool?

        public init(
            token: String,
            serverID: String?,
            librarySectionID: String?,
            connectionPreference: String?,
            hasBooks: Bool? = nil,
            bookLibraryKeys: [String]? = nil,
            includesGenreTaggedBooks: Bool? = nil
        ) {
            self.token = token
            self.serverID = serverID
            self.librarySectionID = librarySectionID
            self.connectionPreference = connectionPreference
            self.hasBooks = hasBooks
            self.bookLibraryKeys = bookLibraryKeys
            self.includesGenreTaggedBooks = includesGenreTaggedBooks
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

    /// An Audiobookshelf login, lent: the server and the iPhone's access
    /// token, never its refresh token. The server hands out a new refresh
    /// token with every renewal and turns the old one away, so two devices
    /// renewing with one would sign each other out. The iPhone renews; the
    /// watch takes its next token (`WatchSyncMessage.credentialsRequest`).
    /// A server before 2.26 has one token that never runs out.
    public struct Audiobookshelf: Codable, Equatable, Sendable {
        public var serverAddress: String
        public var username: String
        public var accessToken: String

        public init(serverAddress: String, username: String, accessToken: String) {
            self.serverAddress = serverAddress
            self.username = username
            self.accessToken = accessToken
        }
    }

    /// Nil when the iPhone isn't signed in to that service.
    public var plex: Plex?
    public var subsonic: Subsonic?
    public var audiobookshelf: Audiobookshelf?

    public init(plex: Plex? = nil, subsonic: Subsonic? = nil, audiobookshelf: Audiobookshelf? = nil) {
        self.plex = plex
        self.subsonic = subsonic
        self.audiobookshelf = audiobookshelf
    }
}
