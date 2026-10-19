import Foundation
import Observation
import os
import Security

/// Client for an Audiobookshelf server: the listener's book libraries,
/// their books, and listening sessions that keep their place and stats.
///
/// Like Subsonic, there's no Sonos-side account: the listener enters a
/// server address and their login in Cue, and the device or a speaker
/// fetches the files straight from the server (see `AudiobookshelfURLs`
/// for the addresses that let a speaker in with no headers).
///
/// Sign-in is the server's own (`POST /login`). Servers from 2.26 hand out
/// an access token lasting an hour and a refresh token that renews it,
/// which is rotated on every renewal; older servers a single token that
/// never expires. Both live in the keychain. A request turned away (401)
/// renews the access token once and tries again.
///
/// Playing a book opens a listening session (`POST /api/items/<id>/play`),
/// whose track URLs need no sign-in while it's open, and is synced every
/// few seconds with where the book is and how much was heard — the server's
/// own apps' way, and the one that counts in its listening stats.
@Observable
public final class AudiobookshelfAPI: DirectStreamProvider {
    public static let shared = AudiobookshelfAPI()

    public static let clientName = "Cue"

    private enum StorageKey {
        static let server = "com.cue.audiobookshelf.server"
        static let username = "com.cue.audiobookshelf.username"
        static let deviceID = "com.cue.audiobookshelf.deviceID"
        static let sessions = "com.cue.audiobookshelf.sessions"
        static let defaultLibrary = "com.cue.audiobookshelf.defaultLibrary"
    }

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let decoder = JSONDecoder()

    /// The server address that answered, with its scheme.
    public private(set) var serverAddress: String
    public private(set) var username: String
    /// Whether a login is held.
    public private(set) var isConfigured: Bool

    /// The library the server opens on for this listener, as it said at
    /// sign-in, until they pick another.
    public var defaultLibraryID: String? {
        didSet { UserDefaults.standard.set(defaultLibraryID, forKey: StorageKey.defaultLibrary) }
    }

    public init(session: URLSession = .shared) {
        self.session = session
        let defaults = UserDefaults.standard
        serverAddress = defaults.string(forKey: StorageKey.server) ?? ""
        username = defaults.string(forKey: StorageKey.username) ?? ""
        defaultLibraryID = defaults.string(forKey: StorageKey.defaultLibrary)
        isConfigured = Self.storedServerURL != nil && Self.storedTokens()?.access != nil
    }

    // MARK: - Signing in

    public enum LoginResult: Equatable, Sendable {
        case success
        case failure(String)
    }

    public struct LoginCheck: Equatable, Sendable {
        public let result: LoginResult
        /// The address that was tried last, with its scheme.
        public let address: String?
    }

    /// Signs in and keeps the login once the server has accepted it.
    ///
    /// A bare host name that looks public is tried over HTTPS first, as
    /// for Subsonic (`SubsonicAPI.checkLogin`): a server on the internet is
    /// nearly always behind TLS, and a password shouldn't cross it in the
    /// clear.
    @MainActor
    public func signIn(address: String, username: String, password: String) async -> LoginCheck {
        guard !username.isEmpty else {
            return LoginCheck(result: .failure("Enter your username."), address: nil)
        }
        var check = LoginCheck(result: .failure("Enter a server address."), address: nil)
        for candidate in Self.candidateAddresses(for: address) {
            guard let base = URL(string: candidate) else { continue }
            let outcome = await login(base: base, username: username, password: password)
            switch outcome {
            case let .signedIn(tokens, defaultLibrary):
                store(address: candidate, username: username, tokens: tokens, defaultLibrary: defaultLibrary)
                return LoginCheck(result: .success, address: candidate)
            case let .refused(message):
                // An Audiobookshelf answer, even a no, means this is the
                // server.
                return LoginCheck(result: .failure(message), address: candidate)
            case let .unreachable(message):
                check = LoginCheck(result: .failure(message), address: candidate)
            }
        }
        return check
    }

    /// Forgets the login, telling the server to end it.
    @MainActor
    public func signOut() async {
        if let base = Self.storedServerURL, let refresh = Self.storedTokens()?.refresh {
            var request = URLRequest(url: base.appending(path: "/logout"))
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.addValue(refresh, forHTTPHeaderField: "x-refresh-token")
            _ = try? await session.data(for: request)
        }
        UserDefaults.standard.removeObject(forKey: StorageKey.server)
        UserDefaults.standard.removeObject(forKey: StorageKey.username)
        UserDefaults.standard.removeObject(forKey: StorageKey.sessions)
        Self.setTokens(nil)
        Self.forgetStoredLogin()
        Self.sessionCache.withLock { $0 = [:] }
        serverAddress = ""
        username = ""
        defaultLibraryID = nil
        isConfigured = false
    }

    struct Tokens: Sendable, Equatable {
        var access: String
        /// Nil on a server older than 2.26, whose one token never expires.
        var refresh: String?
    }

    private enum LoginOutcome {
        case signedIn(Tokens, defaultLibrary: String?)
        case refused(String)
        case unreachable(String)
    }

    private func login(base: URL, username: String, password: String) async -> LoginOutcome {
        var request = URLRequest(url: base.appending(path: "/login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Puts the refresh token in the body rather than only a cookie.
        request.addValue("true", forHTTPHeaderField: "x-return-tokens")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let data: Data
        let http: HTTPURLResponse
        do {
            let (body, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .unreachable("The server didn't answer.") }
            data = body
            http = response
        } catch {
            return .unreachable(SubsonicAPI.message(forConnectionError: error))
        }
        switch http.statusCode {
        case 200:
            guard let response = try? decoder.decode(AudiobookshelfLoginResponse.self, from: data),
                  let access = response.user.accessToken ?? response.user.token else {
                return .unreachable("That address answered, but not as an Audiobookshelf server. Check the port, and the path if it's behind a proxy.")
            }
            return .signedIn(Tokens(access: access, refresh: response.user.refreshToken), defaultLibrary: response.userDefaultLibraryId)
        case 401:
            return .refused("Wrong username or password.")
        case 429:
            return .refused("Too many sign-in attempts. Wait a few minutes and try again.")
        default:
            // A server that only signs in through single sign-on has no
            // password login to answer.
            if let status = await status(base: base), status.app == "audiobookshelf" {
                if let methods = status.authMethods, !methods.contains("local") {
                    return .refused("This server only signs in through single sign-on, which Cue doesn't support yet. Ask its admin to turn on password login.")
                }
                return .refused("The server turned down the sign-in (\(http.statusCode)).")
            }
            return .unreachable("That address answered, but not as an Audiobookshelf server. Check the port, and the path if it's behind a proxy.")
        }
    }

    private func status(base: URL) async -> AudiobookshelfStatus? {
        var request = URLRequest(url: base.appending(path: "/status"))
        request.timeoutInterval = 10
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return try? decoder.decode(AudiobookshelfStatus.self, from: data)
    }

    @MainActor
    private func store(address: String, username: String, tokens: Tokens, defaultLibrary: String?) {
        UserDefaults.standard.set(address, forKey: StorageKey.server)
        UserDefaults.standard.set(username, forKey: StorageKey.username)
        UserDefaults.standard.removeObject(forKey: StorageKey.sessions)
        Self.sessionCache.withLock { $0 = [:] }
        Self.setTokens(tokens)
        Self.forgetStoredLogin()
        serverAddress = address
        self.username = username
        if defaultLibraryID == nil || defaultLibrary != nil {
            defaultLibraryID = defaultLibrary
        }
        isConfigured = true
    }

    /// The addresses to try for what was typed, best first.
    static func candidateAddresses(for raw: String) -> [String] {
        guard let normalized = AudiobookshelfURLs.normalizedAddress(raw) else { return [] }
        guard !raw.contains("://"),
              var components = URLComponents(string: normalized),
              let host = components.host,
              SubsonicAPI.looksPublic(host: host)
        else { return [normalized] }
        components.scheme = "https"
        guard let secure = components.url?.absoluteString else { return [normalized] }
        return [secure, normalized]
    }

    // MARK: - Libraries and books

    /// The listener's book libraries (podcast libraries left out).
    public func libraries() async -> [AudiobookshelfLibrary]? {
        let response: AudiobookshelfLibrariesResponse? = await get("/api/libraries")
        return response?.libraries.filter(\.isBooks)
    }

    /// One page of a library's books, minified (no tracks or chapters).
    /// `sort` is one of the server's sort keys (`media.metadata.title`,
    /// `addedAt`, `media.metadata.authorName`, …).
    public func items(libraryID: String, page: Int, limit: Int = 50, sort: String = "media.metadata.title", descending: Bool = false) async -> AudiobookshelfItemsPage? {
        var query = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "minified", value: "1")
        ]
        if descending {
            query.append(URLQueryItem(name: "desc", value: "1"))
        }
        return await get("/api/libraries/\(libraryID)/items", query: query)
    }

    /// Books started and not finished, across libraries, newest first.
    public func itemsInProgress(limit: Int = 25) async -> [AudiobookshelfItem]? {
        let response: AudiobookshelfInProgress? = await get("/api/me/items-in-progress", query: [URLQueryItem(name: "limit", value: "\(limit)")])
        return response?.libraryItems.filter(\.hasAudio)
    }

    /// A book whole: its files, chapters and where the listener is.
    public func item(id: String) async -> AudiobookshelfItem? {
        await get("/api/items/\(id)", query: [
            URLQueryItem(name: "expanded", value: "1"),
            URLQueryItem(name: "include", value: "progress")
        ])
    }

    public func search(libraryID: String, query: String, limit: Int = 25) async -> [AudiobookshelfItem] {
        let result: AudiobookshelfSearchResult? = await get("/api/libraries/\(libraryID)/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
        return (result?.book ?? []).map(\.libraryItem).filter(\.hasAudio)
    }

    /// Where the listener is in every book, by item id, for the shelves'
    /// progress bars (list pages carry none).
    public func progressByItem() async -> [String: AudiobookshelfMediaProgress]? {
        let user: AudiobookshelfUser? = await get("/api/me")
        guard let progress = user?.mediaProgress else { return nil }
        var byItem: [String: AudiobookshelfMediaProgress] = [:]
        for entry in progress where entry.episodeId == nil {
            guard let id = entry.libraryItemId else { continue }
            byItem[id] = entry
        }
        return byItem
    }

    // MARK: - Listening sessions

    /// Opens a listening session for a book, playing its files directly.
    /// The server ends any session this device had open first, so there's
    /// one at a time.
    public func startSession(itemID: String) async -> AudiobookshelfSession? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let body: [String: Any] = [
            "deviceInfo": [
                "deviceId": Self.deviceID,
                "clientName": Self.clientName,
                "clientVersion": version,
                "manufacturer": "Apple"
            ],
            "supportedMimeTypes": ["audio/mp4", "audio/mpeg", "audio/aac", "audio/flac", "audio/x-m4a", "audio/x-m4b"],
            "mediaPlayer": "AVPlayer",
            // Without it, a file whose type isn't listed is converted to
            // HLS, which no speaker is handed.
            "forceDirectPlay": true
        ]
        guard let (data, status) = await send("POST", "/api/items/\(itemID)/play", json: body), status == 200,
              let opened = try? decoder.decode(AudiobookshelfSession.self, from: data) else { return nil }
        Self.rememberSession(opened.id, for: itemID)
        return opened
    }

    /// Tells the server where the book is and how much was heard since the
    /// last time. With no session open (or one the server has since
    /// dropped), the place is set directly instead, which keeps it but
    /// counts nothing in the stats.
    public func sync(itemID: String, currentTime: TimeInterval, timeListened: TimeInterval, duration: TimeInterval) async {
        if let sessionID = Self.sessionID(for: itemID) {
            let body: [String: Any] = ["currentTime": currentTime, "timeListened": timeListened, "duration": duration]
            if let (_, status) = await send("POST", "/api/session/\(sessionID)/sync", json: body), status == 200 {
                return
            }
            Self.rememberSession(nil, for: itemID)
        }
        await updateProgress(itemID: itemID, currentTime: currentTime, duration: duration, isFinished: false)
    }

    /// Ends the book's session, with a last word on where it got to.
    public func closeSession(itemID: String, currentTime: TimeInterval, duration: TimeInterval) async {
        guard let sessionID = Self.sessionID(for: itemID) else { return }
        Self.rememberSession(nil, for: itemID)
        let body: [String: Any] = ["currentTime": currentTime, "timeListened": 0, "duration": duration]
        _ = await send("POST", "/api/session/\(sessionID)/close", json: body)
    }

    /// Sets where the listener is in a book, or marks it finished or not.
    /// Marking a finished book unfinished takes it back to the start.
    @discardableResult
    public func updateProgress(itemID: String, currentTime: TimeInterval, duration: TimeInterval, isFinished: Bool) async -> Bool {
        var body: [String: Any] = ["currentTime": currentTime, "isFinished": isFinished]
        if duration > 0 {
            body["duration"] = duration
            body["progress"] = min(max(currentTime / duration, 0), 1)
        }
        guard let (_, status) = await send("PATCH", "/api/me/progress/\(itemID)", json: body) else { return false }
        return (200...299).contains(status)
    }

    // MARK: - Media URLs

    /// A book file's URL for `id` (an `AudiobookshelfPartID`): its session
    /// track while the book's session is open, else the file signed with
    /// the access token. Built from storage, so `PlayableContent.uri` can
    /// ask from any thread. Files aren't converted, so `destination` makes
    /// no difference.
    public static func streamURL(for id: String, fileExtension: String?, destination: StreamTranscoding.Destination?) -> URL? {
        guard let part = AudiobookshelfPartID(id), let base = storedServerURL else { return nil }
        if let sessionID = sessionID(for: part.itemID) {
            return AudiobookshelfURLs.sessionTrackURL(base: base, sessionID: sessionID, index: part.index, fileExtension: fileExtension)
        }
        guard let token = storedTokens()?.access else { return nil }
        return AudiobookshelfURLs.fileURL(base: base, itemID: part.itemID, fileID: part.fileID, token: token, fileExtension: fileExtension)
    }

    /// The part id a stream URL plays, read back off a speaker's queue row
    /// (see `AudiobookshelfURLs.partID(fromStreamURL:itemForSession:)`).
    public static func partID(fromStreamURL url: String) -> String? {
        AudiobookshelfURLs.partID(fromStreamURL: url, itemForSession: itemID(forSession:))?.string
    }

    /// The item an open session of this device's plays.
    static func itemID(forSession sessionID: String) -> String? {
        sessionCache.withLock { cache in
            if cache == nil {
                cache = UserDefaults.standard.dictionary(forKey: StorageKey.sessions) as? [String: String] ?? [:]
            }
            return cache?.first { $0.value == sessionID }?.key
        }
    }

    /// The size covers are asked for, as for Plex and Subsonic.
    public static let artworkSize = 1200

    public static func coverURL(itemID: String, width: Int? = artworkSize) -> URL? {
        guard let base = storedServerURL else { return nil }
        return AudiobookshelfURLs.coverURL(base: base, itemID: itemID, width: width)
    }

    // MARK: - Request plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async -> T? {
        guard let (data, status) = await send("GET", path, query: query), status == 200 else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Self.log.error("\(path, privacy: .public): couldn't read the answer: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [], json: [String: Any]? = nil) async -> (Data, Int)? {
        guard let base = Self.storedServerURL else { return nil }
        for attempt in 0..<2 {
            guard let token = Self.storedTokens()?.access else { return nil }
            var url = base.appending(path: path)
            if !query.isEmpty { url.append(queryItems: query) }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 15
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            if let json {
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: json)
            }
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 401, attempt == 0, await renewTokens() {
                continue
            }
            return (data, http.statusCode)
        }
        return nil
    }

    /// One renewal at a time: the refresh token is rotated by each, so two
    /// at once would have the second turned away.
    private let renewal = OSAllocatedUnfairLock<Task<Bool, Never>?>(initialState: nil)

    private func renewTokens() async -> Bool {
        let task = renewal.withLock { running -> Task<Bool, Never> in
            if let running { return running }
            let started = Task { await self.performRenewal() }
            running = started
            return started
        }
        let renewed = await task.value
        renewal.withLock { running in
            if running == task { running = nil }
        }
        return renewed
    }

    private func performRenewal() async -> Bool {
        guard let base = Self.storedServerURL, let refresh = Self.storedTokens()?.refresh else { return false }
        var request = URLRequest(url: base.appending(path: "/auth/refresh"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.addValue(refresh, forHTTPHeaderField: "x-refresh-token")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let renewed = try? decoder.decode(AudiobookshelfLoginResponse.self, from: data),
              let access = renewed.user.accessToken else {
            Self.log.error("couldn't renew the access token")
            return false
        }
        Self.setTokens(Tokens(access: access, refresh: renewed.user.refreshToken ?? refresh))
        return true
    }

    private static let log = Logger(subsystem: "dance.cue", category: "audiobookshelf")

    // MARK: - Stored login

    /// This device's id with the server, made once: the server keeps one
    /// listening session per device.
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: StorageKey.deviceID) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: StorageKey.deviceID)
        return id
    }

    private static let storedServerCache = OSAllocatedUnfairLock<URL??>(initialState: nil)

    /// The stored server's root, read once until the login changes.
    static var storedServerURL: URL? {
        storedServerCache.withLock { cached in
            if let url = cached { return url }
            let url = UserDefaults.standard.string(forKey: StorageKey.server)
                .flatMap { AudiobookshelfURLs.normalizedAddress($0) }
                .flatMap { URL(string: $0) }
            cached = .some(url)
            return url
        }
    }

    private static func forgetStoredLogin() {
        storedServerCache.withLock { $0 = nil }
    }

    /// Open sessions by item id, kept across launches: a session's track
    /// URLs stay good on the server for a day and a half without a sync.
    private static let sessionCache = OSAllocatedUnfairLock<[String: String]?>(initialState: nil)

    static func sessionID(for itemID: String) -> String? {
        sessionCache.withLock { cache in
            if cache == nil {
                cache = UserDefaults.standard.dictionary(forKey: StorageKey.sessions) as? [String: String] ?? [:]
            }
            return cache?[itemID]
        }
    }

    private static func rememberSession(_ sessionID: String?, for itemID: String) {
        let sessions = sessionCache.withLock { cache -> [String: String] in
            var sessions = cache ?? UserDefaults.standard.dictionary(forKey: StorageKey.sessions) as? [String: String] ?? [:]
            // One device, one session: opening another ends the rest on
            // the server.
            if sessionID != nil { sessions.removeAll() }
            sessions[itemID] = sessionID
            cache = sessions
            return sessions
        }
        UserDefaults.standard.set(sessions, forKey: StorageKey.sessions)
    }

    // MARK: - Keychain

    private static let keychainService = "com.cue.audiobookshelf"
    private static let tokenCache = OSAllocatedUnfairLock<Tokens??>(initialState: nil)

    static func storedTokens() -> Tokens? {
        tokenCache.withLock { cached in
            if let tokens = cached { return tokens }
            var tokens: Tokens?
            if let access = keychainRead(account: "access") {
                tokens = Tokens(access: access, refresh: keychainRead(account: "refresh"))
            }
            cached = .some(tokens)
            return tokens
        }
    }

    static func setTokens(_ tokens: Tokens?) {
        tokenCache.withLock { cached in
            keychainWrite(tokens?.access, account: "access")
            keychainWrite(tokens?.refresh, account: "refresh")
            cached = .some(tokens)
        }
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

    /// Replaces the item; nil or empty deletes it.
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
        // After first unlock: file URLs are built from background work while
        // the phone is locked.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
