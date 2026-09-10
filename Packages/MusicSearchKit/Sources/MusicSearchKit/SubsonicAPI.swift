import CryptoKit
import Foundation
import Observation
import os
import Security

/// Client for the Subsonic REST API (Subsonic, Navidrome, Airsonic, Gonic and
/// other compatible self-hosted servers).
///
/// Unlike the streaming services, Subsonic has no Sonos-side account: the user
/// enters a server address and credentials in Cue, and playback streams
/// straight from the server to the speakers over HTTP (`/rest/stream`).
/// Requests authenticate with the salted-token scheme from API 1.13+:
/// `t = md5(password + salt)` — the password itself is never sent.
@Observable
public final class SubsonicAPI: DirectStreamProvider {
    public static let shared = SubsonicAPI()

    public static let apiVersion = "1.16.1"
    public static let clientName = "Cue"

    private enum StorageKey {
        static let server = "com.cue.subsonic.server"
        static let username = "com.cue.subsonic.username"
        /// Legacy pre-keychain locations for the secrets — read once for
        /// migration and cleared; never written to on a working keychain.
        static let password = "com.cue.subsonic.password"
        static let salt = "com.cue.subsonic.salt"
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

    /// Kept in the keychain (with the salt) so stream/cover URLs can be
    /// rebuilt at any time — the URLs carry the derived token, never the
    /// password itself. Changing it rotates the salt so previously issued
    /// URLs (and cached artwork keyed by them) go stale together.
    public var password: String {
        didSet {
            guard password != oldValue else { return }
            if password.isEmpty {
                Self.setSecrets(password: nil, salt: nil)
            } else {
                Self.setSecrets(password: password, salt: Self.makeSalt())
            }
        }
    }

    public var isConfigured: Bool {
        Self.storedServerURL != nil && !username.isEmpty && !password.isEmpty
    }

    public init(session: URLSession = .shared) {
        self.session = session
        let defaults = UserDefaults.standard
        self.serverAddress = defaults.string(forKey: StorageKey.server) ?? ""
        self.username = defaults.string(forKey: StorageKey.username) ?? ""
        // Also migrates a pre-keychain login on first touch.
        self.password = Self.storedSecrets()?.password ?? ""
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
        return await ping(url: url)
    }

    /// Verifies credentials **without** storing them, so a login is only
    /// persisted once the server has actually accepted it.
    public func ping(address: String, username: String, password: String) async -> PingResult {
        guard let normalized = Self.normalizedAddress(address), let base = URL(string: normalized) else {
            return .failure("Enter a server address.")
        }
        guard !username.isEmpty, !password.isEmpty else {
            return .failure("Enter your username and password.")
        }
        guard let url = Self.url(
            endpoint: "ping",
            base: base,
            username: username,
            password: password,
            salt: Self.makeSalt()
        ) else { return .failure("Invalid server address.") }
        return await ping(url: url)
    }

    private func ping(url: URL) async -> PingResult {
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

    /// How many songs the server has indexed, for showing real progress
    /// while the library syncs. `getScanStatus` is the only endpoint that
    /// reports a total, and some servers reserve it for admins — a `nil` here
    /// just means the sync shows a running count instead of a fraction.
    public func librarySongCount() async -> Int? {
        await get("getScanStatus")?.scanStatus?.count
    }

    /// Songs matching a query, paginated. `search3` matches title, artist and
    /// album, so this is the same search the search screen uses, scoped to
    /// songs.
    public func searchSongs(query: String, size: Int = 50, offset: Int = 0) async -> [SubsonicSong] {
        await get("search3", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "songCount", value: "\(size)"),
            URLQueryItem(name: "songOffset", value: "\(offset)"),
            URLQueryItem(name: "albumCount", value: "0"),
            URLQueryItem(name: "artistCount", value: "0")
        ])?.searchResult3?.song ?? []
    }

    /// Albums matching a query, paginated.
    public func searchAlbums(query: String, size: Int = 50, offset: Int = 0) async -> [SubsonicAlbum] {
        await get("search3", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "albumCount", value: "\(size)"),
            URLQueryItem(name: "albumOffset", value: "\(offset)"),
            URLQueryItem(name: "songCount", value: "0"),
            URLQueryItem(name: "artistCount", value: "0")
        ])?.searchResult3?.album ?? []
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
    ///
    /// This overload is the original file, whatever the transcoding setting
    /// — the stable URL `previewURL` and artwork caching key off.
    public static func streamURL(for id: String, fileExtension: String? = nil) -> URL? {
        streamURL(for: id, fileExtension: fileExtension, destination: nil)
    }

    /// The stream URL as `StreamTranscoding` delivers it to `destination`.
    /// With a format chosen, the server transcodes on the fly
    /// (`format=mp3&maxBitRate=192`, per the Subsonic API) and the extension
    /// hint becomes the *transcoded* suffix, since that is what the speaker
    /// will be handed. For a speaker, `estimateContentLength` asks for a
    /// Content-Length on the transcoded stream, which Sonos is happier with
    /// than a bare chunked one; a download on the device is better off
    /// without — a stream that ends short of an estimate is a failed
    /// transfer there. `nil` is the original file.
    public static func streamURL(for id: String, fileExtension: String?, destination: StreamTranscoding.Destination?) -> URL? {
        var queryItems = [URLQueryItem(name: "id", value: id)]
        var hint = fileExtension?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if let destination, let codec = StreamTranscoding.format(for: destination).codec {
            queryItems += [
                URLQueryItem(name: "format", value: codec),
                URLQueryItem(name: "maxBitRate", value: "\(StreamTranscoding.bitrate)")
            ]
            if destination == .speaker {
                queryItems.append(URLQueryItem(name: "estimateContentLength", value: "true"))
            }
            hint = StreamTranscoding.fileExtension(for: destination, original: nil) ?? hint
        }
        guard let url = storedURL(endpoint: "stream", queryItems: queryItems) else { return nil }
        guard !hint.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "ext", value: ".\(hint)")
        ]
        return components.url ?? url
    }

    /// The size the full artwork is asked for, matching Plex's
    /// `PlexImageSize.artwork`: nothing in Cue draws bigger, and the
    /// artwork views never decode bigger. Unsized, `getCoverArt` returns
    /// the original file — several megabytes of 3000px cover for every
    /// tile in a grid, downloaded, cached and decoded for nothing.
    public static let artworkSize = 1200

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
        guard let base = storedServerURL,
              let username = UserDefaults.standard.string(forKey: StorageKey.username), !username.isEmpty,
              let secrets = storedSecrets()
        else { return nil }

        return url(
            endpoint: endpoint,
            base: base,
            username: username,
            password: secrets.password,
            salt: secrets.salt,
            queryItems: queryItems
        )
    }

    /// Builds `<base>/rest/<endpoint>` with the auth parameters appended.
    /// Takes every value explicitly so a candidate login can be checked
    /// before anything is written to storage.
    static func url(
        endpoint: String,
        base: URL,
        username: String,
        password: String,
        salt: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
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
    /// none is stored.
    static var storedServerURL: URL? {
        guard let stored = UserDefaults.standard.string(forKey: StorageKey.server),
              let address = normalizedAddress(stored) else { return nil }
        return URL(string: address)
    }

    /// Reduces whatever the user typed or pasted to the server's REST root.
    ///
    /// Accepts a bare host ("nas.local:4533") by assuming `http`, since most
    /// of these servers live on the LAN. People generally paste the address
    /// from their browser, which carries the *web client's* own route
    /// (`…:4533/app/#/login`) — the fragment, query and that client path are
    /// dropped, while a genuine reverse-proxy subpath (`/subsonic`) is kept,
    /// because the REST API lives under it.
    public static func normalizedAddress(_ raw: String) -> String? {
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        if !address.contains("://") {
            address = "http://\(address)"
        }
        guard var components = URLComponents(string: address),
              let host = components.host, !host.isEmpty else { return nil }

        components.fragment = nil
        components.query = nil
        // Credentials pasted into the URL would otherwise be stored in plain
        // UserDefaults alongside the address; the password belongs in the
        // keychain, entered in its own field.
        components.user = nil
        components.password = nil

        var parts = components.path.split(separator: "/").map(String.init)
        // The API root is whatever precedes the *last* `/rest`, so an
        // already-built REST call collapses back to the server.
        if let restRoot = parts.lastIndex(where: { $0.lowercased() == "rest" }) {
            parts = Array(parts[..<restRoot])
        }
        while let last = parts.last?.lowercased(), ["login", "index.html", "index.php"].contains(last) {
            parts.removeLast()
        }
        // Navidrome's web client is mounted at `/app` and keeps its route in
        // the fragment, so a trailing `app` is the client — but a proxy
        // genuinely mounted at `/app/...` keeps its path.
        if parts.last?.lowercased() == "app" {
            parts.removeLast()
        }
        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")

        guard var result = components.url?.absoluteString else { return nil }
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result.isEmpty ? nil : result
    }

    /// The Subsonic auth token: `md5(password + salt)`, lowercase hex.
    static func token(password: String, salt: String) -> String {
        let digest = Insecure.MD5.hash(data: Data((password + salt).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A fresh random salt, generated whenever the password changes so the
    /// derived token can't outlive the login it was made from.
    private static func makeSalt() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: - Secret storage

    /// The password and salt live in the keychain (`kSecClassGenericPassword`,
    /// after-first-unlock) rather than UserDefaults, so the raw password never
    /// sits in a plaintext plist or device backup. Reads go through an
    /// in-memory cache — stream and cover-art URLs are built per list row, and
    /// a keychain round trip for each would be wasteful.
    private struct SecretsCache {
        var loaded = false
        var secrets: (password: String, salt: String)?
    }

    private static let secretsCache = OSAllocatedUnfairLock(initialState: SecretsCache())
    private static let keychainService = "com.cue.subsonic"

    /// The stored password + salt, migrating a pre-keychain UserDefaults
    /// login into the keychain on first touch.
    static func storedSecrets() -> (password: String, salt: String)? {
        secretsCache.withLock { cache in
            if cache.loaded { return cache.secrets }
            var password = keychainRead(account: "password")
            var salt = keychainRead(account: "salt")
            if password == nil || salt == nil {
                let defaults = UserDefaults.standard
                if let legacyPassword = defaults.string(forKey: StorageKey.password), !legacyPassword.isEmpty,
                   let legacySalt = defaults.string(forKey: StorageKey.salt), !legacySalt.isEmpty {
                    password = legacyPassword
                    salt = legacySalt
                    // Clear the plaintext copies only once the keychain
                    // actually holds them.
                    if keychainWrite(legacyPassword, account: "password"),
                       keychainWrite(legacySalt, account: "salt") {
                        defaults.removeObject(forKey: StorageKey.password)
                        defaults.removeObject(forKey: StorageKey.salt)
                    }
                }
            }
            if let password, let salt, !password.isEmpty, !salt.isEmpty {
                cache.secrets = (password, salt)
            } else {
                cache.secrets = nil
            }
            cache.loaded = true
            return cache.secrets
        }
    }

    /// Stores (or with nils, clears) the password + salt. Falls back to the
    /// legacy UserDefaults location only when the keychain refuses the write,
    /// rather than silently losing the login.
    static func setSecrets(password: String?, salt: String?) {
        secretsCache.withLock { cache in
            let passwordSaved = keychainWrite(password, account: "password")
            let saltSaved = keychainWrite(salt, account: "salt")
            let defaults = UserDefaults.standard
            if passwordSaved && saltSaved {
                defaults.removeObject(forKey: StorageKey.password)
                defaults.removeObject(forKey: StorageKey.salt)
            } else {
                defaults.set(password, forKey: StorageKey.password)
                defaults.set(salt, forKey: StorageKey.salt)
            }
            if let password, let salt, !password.isEmpty, !salt.isEmpty {
                cache.secrets = (password, salt)
            } else {
                cache.secrets = nil
            }
            cache.loaded = true
        }
    }

    /// Testing hook: forget the in-memory cache so the next read hits the
    /// keychain (and the legacy-migration path) again.
    static func resetSecretsCache() {
        secretsCache.withLock { $0 = SecretsCache() }
    }

    private static func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the item (delete + add). A nil/empty value just deletes.
    /// Returns whether the keychain ended up holding the intended state.
    @discardableResult
    private static func keychainWrite(_ value: String?, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        let deleteStatus = SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else {
            return deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
        }
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        // After-first-unlock: URL building can run from background work
        // (queue refresh, artwork prefetch) while the device is locked.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
