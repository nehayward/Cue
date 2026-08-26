import CryptoKit
import Foundation
import Observation

/// Client for the Subsonic REST API (Subsonic, Navidrome, Airsonic, Gonic and
/// other compatible self-hosted servers).
///
/// Unlike the streaming services, Subsonic has no Sonos-side account: the user
/// enters a server address and credentials in Clic, and playback streams
/// straight from the server to the speakers over HTTP (`/rest/stream`).
/// Requests authenticate with the salted-token scheme from API 1.13+:
/// `t = md5(password + salt)` — the password itself is never sent.
@Observable
public final class SubsonicAPI {
    public static let shared = SubsonicAPI()

    public static let apiVersion = "1.16.1"
    public static let clientName = "Clic"

    private enum StorageKey {
        static let server = "com.clic.subsonic.server"
        static let username = "com.clic.subsonic.username"
        static let password = "com.clic.subsonic.password"
        static let salt = "com.clic.subsonic.salt"
    }

    private let session: URLSession
    private let decoder = JSONDecoder()

    /// The server address as the user typed it (e.g. "navidrome.local:4533"
    /// or "https://music.example.com"). A missing scheme defaults to `http`,
    /// since most Subsonic servers live on the LAN — where the speakers must
    /// be able to reach them anyway.
    public var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: StorageKey.server) }
    }

    public var username: String {
        didSet { UserDefaults.standard.set(username, forKey: StorageKey.username) }
    }

    /// Stored so stream/cover URLs can be rebuilt at any time — they carry the
    /// derived token, never the password itself. Changing it rotates the salt
    /// so previously issued URLs (and cached artwork keyed by them) go stale
    /// together.
    public var password: String {
        didSet {
            UserDefaults.standard.set(password, forKey: StorageKey.password)
            Self.rotateSalt()
        }
    }

    public var isConfigured: Bool {
        Self.storedServerURL != nil && !username.isEmpty && !password.isEmpty
    }

    public var serverURL: URL? { Self.storedServerURL }

    public init(session: URLSession = .shared) {
        self.session = session
        let defaults = UserDefaults.standard
        self.serverAddress = defaults.string(forKey: StorageKey.server) ?? ""
        self.username = defaults.string(forKey: StorageKey.username) ?? ""
        self.password = defaults.string(forKey: StorageKey.password) ?? ""
        if defaults.string(forKey: StorageKey.salt) == nil, !password.isEmpty {
            Self.rotateSalt()
        }
    }

    // MARK: - Connection

    public enum PingResult: Equatable, Sendable {
        case success
        case failure(String)
    }

    /// Verifies the stored server address and credentials.
    public func ping() async -> PingResult {
        guard Self.storedServerURL != nil else { return .failure("Enter a server address.") }
        guard let url = Self.storedURL(endpoint: "ping") else { return .failure("Invalid server address.") }
        do {
            let (data, _) = try await session.data(for: URLRequest(url: url))
            guard let body = try? decoder.decode(SubsonicEnvelope.self, from: data).subsonicResponse else {
                return .failure("Not a Subsonic server.")
            }
            if body.isOK { return .success }
            return .failure(body.error?.message ?? "Server returned an error.")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Search

    public func search(query: String, songCount: Int = 20, albumCount: Int = 10, artistCount: Int = 5) async -> SubsonicSearchResult3? {
        await get("search3", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "songCount", value: "\(songCount)"),
            URLQueryItem(name: "albumCount", value: "\(albumCount)"),
            URLQueryItem(name: "artistCount", value: "\(artistCount)")
        ])?.searchResult3
    }

    // MARK: - Lookups

    public func song(for id: String) async -> SubsonicSong? {
        await get("getSong", queryItems: [URLQueryItem(name: "id", value: id)])?.song
    }

    /// The album with its songs populated.
    public func album(for id: String) async -> SubsonicAlbum? {
        await get("getAlbum", queryItems: [URLQueryItem(name: "id", value: id)])?.album
    }

    /// The artist with their albums populated.
    public func artist(for id: String) async -> SubsonicArtist? {
        await get("getArtist", queryItems: [URLQueryItem(name: "id", value: id)])?.artist
    }

    /// The playlist with its songs populated.
    public func playlist(for id: String) async -> SubsonicPlaylist? {
        await get("getPlaylist", queryItems: [URLQueryItem(name: "id", value: id)])?.playlist
    }

    // MARK: - Library

    public func playlists() async -> [SubsonicPlaylist] {
        await get("getPlaylists")?.playlists?.playlist ?? []
    }

    /// `type` is a Subsonic list type: `newest`, `recent`, `frequent`,
    /// `random`, `alphabeticalByName`, `starred`, …
    public func albumList(type: String, size: Int = 50, offset: Int = 0) async -> [SubsonicAlbum] {
        await get("getAlbumList2", queryItems: [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])?.albumList2?.album ?? []
    }

    public func artists() async -> [SubsonicArtist] {
        let indexes = await get("getArtists")?.artists?.index ?? []
        return indexes.flatMap { $0.artist ?? [] }
    }

    public func randomSongs(size: Int = 50) async -> [SubsonicSong] {
        await get("getRandomSongs", queryItems: [URLQueryItem(name: "size", value: "\(size)")])?.randomSongs?.song ?? []
    }

    /// Every song in the library, paginated. `search3` with an empty query,
    /// which OpenSubsonic servers (Navidrome, …) define as "match everything";
    /// older servers may return nothing, and callers degrade gracefully.
    public func songs(size: Int = 50, offset: Int = 0) async -> [SubsonicSong] {
        await get("search3", queryItems: [
            URLQueryItem(name: "query", value: ""),
            URLQueryItem(name: "songCount", value: "\(size)"),
            URLQueryItem(name: "songOffset", value: "\(offset)"),
            URLQueryItem(name: "albumCount", value: "0"),
            URLQueryItem(name: "artistCount", value: "0")
        ])?.searchResult3?.song ?? []
    }

    public func starred() async -> SubsonicStarred? {
        await get("getStarred2")?.starred2
    }

    // MARK: - Playlist management

    /// Creates a playlist, optionally seeded with songs, and returns it.
    public func createPlaylist(name: String, songIDs: [String] = []) async -> SubsonicPlaylist? {
        var items = [URLQueryItem(name: "name", value: name)]
        items += songIDs.map { URLQueryItem(name: "songId", value: $0) }
        guard let body = await get("createPlaylist", queryItems: items) else { return nil }
        if let playlist = body.playlist { return playlist }
        // API < 1.14 returns a bare ok — recover the new playlist by name.
        return await playlists().last { $0.name == name }
    }

    @discardableResult
    public func addToPlaylist(id: String, songIDs: [String]) async -> Bool {
        guard !songIDs.isEmpty else { return true }
        var items = [URLQueryItem(name: "playlistId", value: id)]
        items += songIDs.map { URLQueryItem(name: "songIdToAdd", value: $0) }
        return await get("updatePlaylist", queryItems: items)?.isOK ?? false
    }

    /// Removes the songs at `indexes` (0-based positions within the playlist —
    /// the API removes by position, not by song id).
    @discardableResult
    public func removeFromPlaylist(id: String, indexes: [Int]) async -> Bool {
        guard !indexes.isEmpty else { return true }
        var items = [URLQueryItem(name: "playlistId", value: id)]
        items += indexes.map { URLQueryItem(name: "songIndexToRemove", value: "\($0)") }
        return await get("updatePlaylist", queryItems: items)?.isOK ?? false
    }

    @discardableResult
    public func deletePlaylist(id: String) async -> Bool {
        await get("deletePlaylist", queryItems: [URLQueryItem(name: "id", value: id)])?.isOK ?? false
    }

    // MARK: - Artist extras

    /// The artist's most-played songs. Keyed by name (not id) per the API;
    /// servers without play data (e.g. Navidrome with Last.fm off) return [].
    public func topSongs(artistName: String, count: Int = 20) async -> [SubsonicSong] {
        await get("getTopSongs", queryItems: [
            URLQueryItem(name: "artist", value: artistName),
            URLQueryItem(name: "count", value: "\(count)")
        ])?.topSongs?.song ?? []
    }

    // MARK: - Favorites

    @discardableResult
    public func star(id: String) async -> Bool {
        await get("star", queryItems: [URLQueryItem(name: "id", value: id)])?.isOK ?? false
    }

    @discardableResult
    public func unstar(id: String) async -> Bool {
        await get("unstar", queryItems: [URLQueryItem(name: "id", value: id)])?.isOK ?? false
    }

    public func isStarred(id: String) async -> Bool {
        await song(for: id)?.starred != nil
    }

    // MARK: - Media URLs

    /// The direct stream URL for a song — this is what the Sonos speaker
    /// plays. Static and backed by `UserDefaults` so `PlayableContent.uri`
    /// can rebuild it synchronously from any thread. The salt only rotates
    /// when the password changes, keeping the URL stable for a given login —
    /// queue rows survive relaunches and artwork caching stays keyed to one
    /// URL.
    ///
    /// `fileExtension` (the song's `suffix`, e.g. "flac") is appended as a
    /// trailing `ext=.flac` parameter. The server ignores the unknown
    /// parameter; Sonos classifies plain-HTTP queue items by the extension it
    /// finds in the URL and rejects extension-less ones with UPnP error 804,
    /// since `/rest/stream?id=…` gives it nothing to sniff.
    public static func streamURL(for id: String, fileExtension: String? = nil) -> URL? {
        guard let url = storedURL(endpoint: "stream", queryItems: [URLQueryItem(name: "id", value: id)]) else { return nil }
        guard let fileExtension = fileExtension?.trimmingCharacters(in: .whitespaces).lowercased(),
              !fileExtension.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "ext", value: ".\(fileExtension)")
        ]
        return components.url ?? url
    }

    /// Cover art URL for a `coverArt` id. `size` asks the server to scale.
    public static func coverArtURL(for coverID: String?, size: Int? = nil) -> URL? {
        guard let coverID, !coverID.isEmpty else { return nil }
        var items = [URLQueryItem(name: "id", value: coverID)]
        if let size {
            items.append(URLQueryItem(name: "size", value: "\(size)"))
        }
        return storedURL(endpoint: "getCoverArt", queryItems: items)
    }

    // MARK: - Request plumbing

    private func get(_ endpoint: String, queryItems: [URLQueryItem] = []) async -> SubsonicResponseBody? {
        guard let url = Self.storedURL(endpoint: endpoint, queryItems: queryItems) else { return nil }
        guard let (data, _) = try? await session.data(for: URLRequest(url: url)) else { return nil }
        guard let body = try? decoder.decode(SubsonicEnvelope.self, from: data).subsonicResponse,
              body.isOK else { return nil }
        return body
    }

    /// Builds `<server>/rest/<endpoint>` with the auth parameters appended.
    /// Reads everything from `UserDefaults` so it works without touching the
    /// observable instance (safe from `PlayableContent.uri` on any thread).
    static func storedURL(endpoint: String, queryItems: [URLQueryItem] = []) -> URL? {
        let defaults = UserDefaults.standard
        guard let base = storedServerURL,
              let username = defaults.string(forKey: StorageKey.username), !username.isEmpty,
              let password = defaults.string(forKey: StorageKey.password), !password.isEmpty,
              let salt = defaults.string(forKey: StorageKey.salt), !salt.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }

        components.path = components.path.appending("/rest/\(endpoint)")
        components.queryItems = queryItems + [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token(password: password, salt: salt)),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json")
        ]
        return components.url
    }

    /// The normalized base URL for the stored server address, or `nil` when
    /// none is stored. Accepts bare hosts ("nas.local:4533") by assuming
    /// `http`, and drops a trailing slash so path appending stays clean.
    static var storedServerURL: URL? {
        guard var address = UserDefaults.standard.string(forKey: StorageKey.server)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else { return nil }
        if !address.contains("://") {
            address = "http://\(address)"
        }
        while address.hasSuffix("/") {
            address.removeLast()
        }
        guard let url = URL(string: address), url.host != nil else { return nil }
        return url
    }

    /// The Subsonic auth token: `md5(password + salt)`, lowercase hex.
    static func token(password: String, salt: String) -> String {
        let digest = Insecure.MD5.hash(data: Data((password + salt).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Generates and stores a fresh random salt. Called whenever the password
    /// changes so the derived token can't outlive the login it was made from.
    private static func rotateSalt() {
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(salt, forKey: StorageKey.salt)
    }
}
