import Foundation

public final class DeezerAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Search

    public func search(for query: String, limit: Int = 10) async -> [DeezerTrack] {
        await fetchList("/search", queryItems: [.q(query), .limit(limit)])
    }

    public func searchAlbums(for query: String, limit: Int = 5) async -> [DeezerAlbum] {
        await fetchList("/search/album", queryItems: [.q(query), .limit(limit)])
    }

    public func searchArtists(for query: String, limit: Int = 5) async -> [DeezerArtist] {
        await fetchList("/search/artist", queryItems: [.q(query), .limit(limit)])
    }

    public func searchPlaylists(for query: String, limit: Int = 5) async -> [DeezerPlaylist] {
        await fetchList("/search/playlist", queryItems: [.q(query), .limit(limit)])
    }

    // MARK: - Lookup

    public func track(for id: String) async -> DeezerTrack? { await fetch("/track/\(id)") }
    public func album(for id: String) async -> DeezerAlbum? { await fetch("/album/\(id)") }
    public func artist(for id: String) async -> DeezerArtist? { await fetch("/artist/\(id)") }
    public func playlist(for id: String) async -> DeezerPlaylist? { await fetch("/playlist/\(id)") }

    public func albumTracks(for id: String) async -> [DeezerTrack] {
        await fetchList("/album/\(id)/tracks", queryItems: [.limit(50)])
    }

    public func artistTopTracks(for id: String, limit: Int = 20) async -> [DeezerTrack] {
        await fetchList("/artist/\(id)/top", queryItems: [.limit(limit)])
    }

    public func artistAlbums(for id: String, limit: Int = 20) async -> [DeezerAlbum] {
        await fetchList("/artist/\(id)/albums", queryItems: [.limit(limit)])
    }

    public func playlistTracks(for id: String) async -> [DeezerTrack] {
        await fetchList("/playlist/\(id)/tracks", queryItems: [.limit(50)])
    }

    // MARK: - User library (requires Deezer OAuth token)

    public func userFavoriteTracks(accessToken: String, index: Int = 0, limit: Int = 50) async -> [DeezerTrack] {
        await fetchList("/user/me/tracks", queryItems: .authed(token: accessToken, index: index, limit: limit))
    }

    public func userFavoriteAlbums(accessToken: String, index: Int = 0, limit: Int = 50) async -> [DeezerAlbum] {
        await fetchList("/user/me/albums", queryItems: .authed(token: accessToken, index: index, limit: limit))
    }

    public func userFavoriteArtists(accessToken: String, index: Int = 0, limit: Int = 50) async -> [DeezerArtist] {
        await fetchList("/user/me/artists", queryItems: .authed(token: accessToken, index: index, limit: limit))
    }

    public func userPlaylists(accessToken: String, index: Int = 0, limit: Int = 50) async -> [DeezerPlaylist] {
        await fetchList("/user/me/playlists", queryItems: .authed(token: accessToken, index: index, limit: limit))
    }

    public func userHistory(accessToken: String, limit: Int = 25) async -> [DeezerTrack] {
        await fetchList("/user/me/history", queryItems: .authed(token: accessToken, index: 0, limit: limit))
    }

    /// The authenticated user's numeric id.
    public func currentUserID(accessToken: String) async -> Int? {
        let user: DeezerUser? = await fetch("/user/me", queryItems: [URLQueryItem(name: "access_token", value: accessToken)])
        return user?.id
    }

    /// Whether the playlist is owned by `userID` (Deezer only lets you edit your own playlists).
    public func isPlaylistEditable(id: String, ownedBy userID: Int) async -> Bool {
        guard let details = await playlist(for: id) else { return false }
        return details.user?.id == userID
    }

    // MARK: - Playlist management (requires the `manage_library` OAuth scope)

    /// Creates a new playlist for the authenticated user. Returns the new playlist id.
    public func createPlaylist(title: String, accessToken: String) async -> String? {
        guard let url = deezerURL("/user/me/playlists", queryItems: [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "access_token", value: accessToken)
        ]) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        guard let (data, _) = try? await session.data(for: request),
              let response = try? decoder.decode(DeezerCreatePlaylistResponse.self, from: data) else { return nil }
        return String(response.id)
    }

    /// Adds tracks (by Deezer track id) to a playlist.
    public func addTracks(playlistID: String, trackIDs: [String], accessToken: String) async -> Bool {
        guard !trackIDs.isEmpty else { return true }
        return await mutate("/playlist/\(playlistID)/tracks", method: "POST",
                            queryItems: [URLQueryItem(name: "songs", value: trackIDs.joined(separator: ","))],
                            accessToken: accessToken)
    }

    /// Removes tracks (by Deezer track id) from a playlist.
    public func removeTracks(playlistID: String, trackIDs: [String], accessToken: String) async -> Bool {
        guard !trackIDs.isEmpty else { return true }
        return await mutate("/playlist/\(playlistID)/tracks", method: "DELETE",
                            queryItems: [URLQueryItem(name: "songs", value: trackIDs.joined(separator: ","))],
                            accessToken: accessToken)
    }

    /// Deletes a playlist owned by the authenticated user.
    public func deletePlaylist(playlistID: String, accessToken: String) async -> Bool {
        await mutate("/playlist/\(playlistID)", method: "DELETE", queryItems: [], accessToken: accessToken)
    }

    /// Deezer mutation endpoints return the bare JSON literal `true` on success, or an error object.
    private func mutate(_ path: String, method: String, queryItems: [URLQueryItem], accessToken: String) async -> Bool {
        var items = queryItems
        items.append(URLQueryItem(name: "access_token", value: accessToken))
        guard let url = deezerURL(path, queryItems: items) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = method
        guard let (data, _) = try? await session.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return false }
        return (object as? Bool) ?? false
    }

    // MARK: - Favorites via Sonos SMAPI

    public func rateItem(credentials: SMAPICredentials, smapiID: String, rating: Int) async -> Bool {
        let envelope = SMAPIEnvelope(credentials: credentials, action: .rateItem(id: smapiID, rating: rating))
        return await smapi(envelope) { _ in true } ?? false
    }

    public func isItemLiked(credentials: SMAPICredentials, smapiID: String) async -> Bool {
        let envelope = SMAPIEnvelope(credentials: credentials, action: .getExtendedMetadata(id: smapiID))
        return await smapi(envelope) { xml in
            guard let range = xml.range(of: "ISFAVORITE") else { return false }
            return String(xml[range.upperBound...]).contains(">1<")
        } ?? false
    }

    // MARK: - Helpers

    private func fetch<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async -> T? {
        guard let url = deezerURL(path, queryItems: queryItems),
              let (data, _) = try? await session.data(for: URLRequest(url: url)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func fetchList<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async -> [T] {
        await (fetch(path, queryItems: queryItems) as DeezerContainer<T>?)?.data ?? []
    }

    private func smapi<T>(_ envelope: SMAPIEnvelope, parse: (String) -> T) async -> T? {
        guard let url = URL(string: "https://api.deezer.com/sonos") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\"http://www.sonos.com/Services/1.1#\(envelope.action.soapAction)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = envelope.xml.data(using: .utf8)
        guard let (data, _) = try? await session.data(for: request),
              let xml = String(data: data, encoding: .utf8) else { return nil }
        return parse(xml)
    }

    private func deezerURL(_ path: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.deezer.com"
        components.path = path
        if !queryItems.isEmpty { components.queryItems = queryItems }
        return components.url
    }
}

// MARK: - Response models

private struct DeezerCreatePlaylistResponse: Decodable {
    let id: Int
}

// MARK: - URLQueryItem helpers

private extension URLQueryItem {
    static func q(_ value: String) -> URLQueryItem { URLQueryItem(name: "q", value: value) }
    static func limit(_ value: Int) -> URLQueryItem { URLQueryItem(name: "limit", value: "\(value)") }
}

private extension [URLQueryItem] {
    static func authed(token: String, index: Int, limit: Int) -> [URLQueryItem] {[
        URLQueryItem(name: "access_token", value: token),
        URLQueryItem(name: "limit", value: "\(limit)"),
        URLQueryItem(name: "index", value: "\(index)")
    ]}
}
