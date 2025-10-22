import Foundation

public final class TidalAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    public func search(for query: String, limit: Int = 20) async -> TidalResult? {
        if query.count < 1 { return nil }
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/v2/searchResults/\(query)"
        components.queryItems = [
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "tracks.albums,artists.profileArt,albums.coverArt,playlists.coverArt")
        ]

        guard let url = components.url else {
            return nil
        }

        do {
            guard let tidalResponse: TidalApiResponse? = try await loadAuthorized(url) else {
                return nil
            }
            return tidalResponse?.toTidalResult
        } catch {

            return nil
        }
    }

    public func track(with id: String) async -> TidalTrackResource? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/v2/tracks/\(id)"
        components.queryItems = [
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "artists,albums")
        ]

        guard let url = components.url else {
            return nil
        }

        struct TrackResult: Codable {
            let data: TidalIncluded
            let included: [TidalIncluded]?
        }

        guard let result: TrackResult = try? await loadAuthorized(url),
              let albumResult = result.included?.first(where: { $0.type.lowercased().contains("album") }),
              let artistResult = result.included?.first(where: { $0.type.lowercased().contains("artist") }),
              let albumAttrs = albumResult.attributes,
              let artistAttrs = artistResult.attributes,
              let dataAttrs = result.data.attributes else { return nil}
        
        let artist = TidalArtistResource(
            id: artistResult.id,
            name: artistAttrs.label,
            picture: artistAttrs.tidalImages,
            main: true,
            tidalUrl: artistAttrs.tidalURL,
            popularity: artistAttrs.popularityRating
        )
        
        let album = TidalAlbumResource(
            id: albumResult.id,
            barcodeId: albumAttrs.barcodeId,
            title: albumAttrs.title ?? "",
            artists: [artist],
            duration: albumAttrs.durationInSeconds,
            releaseDate: albumAttrs.releaseDate,
            imageCover: albumAttrs.tidalImages,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: albumAttrs.tidalURL,
            properties: nil,
            mediaMetadata: albumAttrs.mediaTags,
            isExplicit: albumAttrs.isExplicit,
            popularity: albumAttrs.popularityRating
        )

        return TidalTrackResource(
            id: result.data.id,
            isrc: dataAttrs.isrc,
            title:  dataAttrs.label,
            artists: [artist],
            album: album,
            duration: dataAttrs.durationInSeconds,
            releaseDate: dataAttrs.releaseDate,
            imageCover: albumAttrs.tidalImages,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: dataAttrs.tidalURL,
            mediaMetadata: dataAttrs.mediaTags,
            isExplicit: dataAttrs.isExplicit,
            popularity: dataAttrs.popularityRating
        )
    }

    public func album(with id: String) async -> TidalAlbumResource? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/v2/albums/\(id)"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "artists")
        ]

        guard let url = components.url else {
            return nil
        }
        
        struct Result: Codable {
            let data: TidalIncluded
            let included: [TidalIncluded]?
        }

        guard let album: Result = try? await loadAuthorized(url),
              let artistResult = album.included?.first(where: { $0.type.lowercased().contains("artist") }),
              let artistAttrs = artistResult.attributes,
              let albumAttrs = album.data.attributes else { return nil}
        
        let artist = TidalArtistResource(
            id: artistResult.id,
            name: artistAttrs.label,
            picture: artistAttrs.tidalImages,
            main: true,
            tidalUrl: artistAttrs.tidalURL,
            popularity: artistAttrs.popularityRating
        )
        
        return TidalAlbumResource(
            id: album.data.id,
            barcodeId: albumAttrs.barcodeId,
            title: albumAttrs.title ?? "",
            artists: [artist],
            duration: albumAttrs.durationInSeconds,
            releaseDate: albumAttrs.releaseDate,
            imageCover: albumAttrs.tidalImages,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: albumAttrs.tidalURL,
            properties: nil,
            mediaMetadata: albumAttrs.mediaTags,
            isExplicit: albumAttrs.isExplicit,
            popularity: albumAttrs.popularityRating
        )
    }

    public func albumSongs(id: String) async -> [TidalTrackResource] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/v2/albums/\(id)"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "items,artists")
        ]

        guard let url = components.url else {
            return []
        }

        struct AlbumResult: Codable {
            let data: TidalIncluded
            let included: [TidalIncluded]
        }

        guard let albumResult: AlbumResult = try? await loadAuthorized(url),
              let artistResult = albumResult.included.first(where: { $0.type.lowercased().contains("artist") }),
              let artistAttrs = artistResult.attributes,
              let albumAttrs = albumResult.data.attributes else { return [] }
        
        let artist = TidalArtistResource(
            id: artistResult.id,
            name: artistAttrs.label,
            picture: artistAttrs.tidalImages,
            main: true,
            tidalUrl: artistAttrs.tidalURL,
            popularity: artistAttrs.popularityRating
        )
        
        let album = TidalAlbumResource(
            id: albumResult.data.id,
            barcodeId: albumAttrs.barcodeId,
            title: albumAttrs.title ?? "",
            artists: [artist],
            duration: albumAttrs.durationInSeconds,
            releaseDate: albumAttrs.releaseDate,
            imageCover: albumAttrs.tidalImages,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: albumAttrs.tidalURL,
            properties: nil,
            mediaMetadata: albumAttrs.mediaTags,
            isExplicit: albumAttrs.isExplicit,
            popularity: albumAttrs.popularityRating
        )
        
        return albumResult.included.compactMap {
            guard let trackAttrs = $0.attributes else { return nil }
            return TidalTrackResource(
                id: $0.id,
                isrc: trackAttrs.isrc,
                title: trackAttrs.title ?? "",
                artists: [],
                album: album,
                duration: trackAttrs.durationInSeconds,
                releaseDate: nil,
                imageCover: [],
                numberOfVolumes: nil,
                numberOfTracks: nil,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: "",
                mediaMetadata: nil,
                isExplicit: trackAttrs.isExplicit,
                popularity: trackAttrs.popularityRating
            )
        }
    }

    public func artistSongs(id: String) async -> [TidalTrackResource] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/v2/artists/\(id)"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "tracks"),
            URLQueryItem(name: "collapseBy", value: "FINGERPRINT"),
        ]

        guard let url = components.url else {
            return []
        }

        struct Result: Codable {
            let data: TidalIncluded
            let included: [TidalIncluded]?
        }

        guard let result: Result = try? await loadAuthorized(url),
              let tracks = result.included,
              let artistAttrs = result.data.attributes else { return [] }
        
        let artist = TidalArtistResource(
            id: result.data.id,
            name: artistAttrs.label,
            picture: artistAttrs.tidalImages,
            main: true,
            tidalUrl: artistAttrs.tidalURL,
            popularity: artistAttrs.popularityRating
        )
        
        return tracks.compactMap {
            guard let trackAttrs = $0.attributes else { return nil }
            return TidalTrackResource(
                id: $0.id,
                isrc: trackAttrs.isrc,
                title: trackAttrs.label,
                artists: [artist],
                album: nil,
                duration: trackAttrs.durationInSeconds,
                releaseDate: trackAttrs.releaseDate,
                imageCover: trackAttrs.tidalImages,
                numberOfVolumes: trackAttrs.numberOfVolumes,
                numberOfTracks: trackAttrs.numberOfItems,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: trackAttrs.tidalURL,
                mediaMetadata: trackAttrs.mediaTags,
                isExplicit: trackAttrs.isExplicit,
                popularity: trackAttrs.popularityRating
            )
        }
    }

    public func artistAlbums(id: String) async -> [TidalAlbumResource] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/v2/artists/\(id)"
        components.queryItems = [
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "albums"),
        ]


        guard let url = components.url else {
            return []
        }

        struct AlbumResult: Codable {
            let data: TidalIncluded
            let included: [TidalIncluded]?
        }

        guard let result: AlbumResult = try? await loadAuthorized(url),
              let albums = result.included,
              let artistAttrs = result.data.attributes else { return [] }
        
        let artist = TidalArtistResource(
            id: result.data.id,
            name: artistAttrs.label,
            picture: artistAttrs.tidalImages,
            main: true,
            tidalUrl: artistAttrs.tidalURL,
            popularity: artistAttrs.popularityRating
        )
        
        return albums.compactMap {
            guard let albumAttrs = $0.attributes else { return nil }
            return TidalAlbumResource(
                id: $0.id,
                barcodeId: albumAttrs.barcodeId,
                title: albumAttrs.label,
                artists: [artist],
                duration: albumAttrs.durationInSeconds,
                releaseDate: albumAttrs.releaseDate,
                imageCover: albumAttrs.tidalImages,
                numberOfVolumes: albumAttrs.numberOfVolumes,
                numberOfTracks: albumAttrs.numberOfItems,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: albumAttrs.tidalURL,
                properties: nil,
                mediaMetadata: albumAttrs.mediaTags,
                isExplicit: albumAttrs.isExplicit,
                popularity: albumAttrs.popularityRating
            )
        }
    }

    public func artist(with id: String) async -> TidalArtistResource? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/v2/artists/\(id)"
        components.queryItems = [
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
        ]

        guard let url = components.url else {
            return nil
        }

        struct AlbumResult: Codable {
            let data: TidalIncluded
            let included: [TidalIncluded]?
        }

        guard let result: AlbumResult = try? await loadAuthorized(url),
              let artistAttrs = result.data.attributes else { return nil }
        
        let artist = TidalArtistResource(
            id: result.data.id,
            name: artistAttrs.label,
            picture: artistAttrs.tidalImages,
            main: true,
            tidalUrl: artistAttrs.tidalURL,
            popularity: artistAttrs.popularityRating
        )
        
        return artist
    }
    
    public func playlist(with id: String, cursor: String? = nil) async -> ([TidalTrackResource], String?)? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/v2/playlists/\(id)/relationships/items"
        components.queryItems = [
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "items,coverArt")
        ]
        
        // Only add cursor if it's not nil
        if let cursor = cursor {
            components.queryItems?.append(URLQueryItem(name: "page[cursor]", value: cursor))
        }
        
        guard let url = components.url else {
            return nil
        }

        do {
            guard let tidalResponse: TidalApiResponsePlaylistItems = try await loadAuthorized(url) else {
                return nil
            }
            return (tidalResponse.toTidalResult.tracks, tidalResponse.links?.meta?.nextCursor)
        } catch {

            return nil
        }
    }

    func getToken() async -> TidalTokenResponse? {
        guard let URL = URL(string: "https://auth.tidal.com/v1/oauth2/token") else { return nil }
        var request = URLRequest(url: URL)
        request.httpMethod = "POST"
        request.addValue("Basic NlhINER0MEZnR3gzVEhaNjp2U0szVW5Pc3libzcyRDB2Nlp0emlGSUVyVFZIa29IbGo0a0xWUmdKY3pBPQ==", forHTTPHeaderField: "Authorization")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let spotifySearch = try decoder.decode(TidalTokenResponse.self, from: data)
            return spotifySearch
        } catch {
            print(String(decoding: data, as: UTF8.self))
            return nil
        }
    }

    // MARK: Token

    private var currentToken: Token?
    private var refreshTask: Task<Token, Error>?

    enum AuthError: Error {
        case missingToken
        case invalidToken
    }

    func loadAuthorized<T: Decodable>(_ url: URL, allowRetry: Bool = true) async throws -> T {
        let request = try await authorizedRequest(from: url)
        let (data, urlResponse) = try await session.data(for: request)

        // check the http status code and refresh + retry if we received 401 Unauthorized
        if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
            if allowRetry {
                _ = try await refreshToken()
                return try await loadAuthorized(url, allowRetry: false)
            }

            throw AuthError.invalidToken
        }

        do {
            let response = try decoder.decode(T.self, from: data)
            return response
        } catch {
            print(error)
            print("Failed to decode ⚠️")
            print(String(decoding: data, as: UTF8.self))
//            assertionFailure(String(decoding: data, as: UTF8.self))
            throw error
        }
    }

    private func authorizedRequest(from url: URL) async throws -> URLRequest {
        var urlRequest = URLRequest(url: url)
        let token = try await validToken()
        urlRequest.setValue("Bearer \(token.id)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    func validToken() async throws -> Token {
        if let handle = refreshTask {
            return try await handle.value
        }

        guard let token = currentToken else {
            return try await refreshToken()
//            throw AuthError.missingToken
        }

        if token.isValid {
            return token
        }

        return try await refreshToken()
    }

    func refreshToken() async throws -> Token {
        if let refreshTask = refreshTask {
            return try await refreshTask.value
        }

        let task = Task { () throws -> Token in
            defer { refreshTask = nil }

            guard let response = await getToken() else {
                throw AuthError.missingToken
            }

            let newToken = Token(validUntil: Date.now.addingTimeInterval(TimeInterval(response.expiresIn)), id: response.accessToken)
            currentToken = newToken
            return newToken
        }

        self.refreshTask = task
        return try await task.value
    }
}

extension TidalAPI {
    struct Token {
        let validUntil: Date
        let id: String
        var isValid: Bool { Date.now < validUntil }
    }
}
