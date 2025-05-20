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
        components.path = "/v2/searchresults/\(query)"
        components.queryItems = [
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "tracks,artists,albums")
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
              let artistResult = result.included?.first(where: { $0.type.lowercased().contains("artist") }) else { return nil}
        
        let artist = TidalArtistResource(
            id: artistResult.id,
            name: artistResult.attributes.label,
            picture: artistResult.attributes.tidalImages,
            main: true,
            tidalUrl: artistResult.attributes.tidalURL,
            popularity: artistResult.attributes.popularityRating
        )
        
        let album = TidalAlbumResource(
            id: albumResult.id,
            barcodeId: albumResult.attributes.barcodeId,
            title: albumResult.attributes.title ?? "",
            artists: [artist],
            duration: albumResult.attributes.durationInSeconds,
            releaseDate: albumResult.attributes.releaseDate,
            imageCover: albumResult.attributes.tidalImages,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: albumResult.attributes.tidalURL,
            properties: nil,
            mediaMetadata: albumResult.attributes.mediaTags,
            isExplicit: albumResult.attributes.isExplicit,
            popularity: albumResult.attributes.popularityRating
        )

        return TidalTrackResource(
            id: result.data.id,
            isrc: result.data.attributes.isrc,
            title:  result.data.attributes.label,
            artists: [artist],
            album: album,
            duration: result.data.attributes.durationInSeconds,
            releaseDate: result.data.attributes.releaseDate,
            imageCover: albumResult.attributes.tidalImages,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: result.data.attributes.tidalURL,
            mediaMetadata: result.data.attributes.mediaTags,
            isExplicit: result.data.attributes.isExplicit,
            popularity: result.data.attributes.popularityRating
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
              let artistResult = album.included?.first(where: { $0.type.lowercased().contains("artist") }) else { return nil}
        
        let artist = TidalArtistResource(
            id: artistResult.id,
            name: artistResult.attributes.label,
            picture: artistResult.attributes.tidalImages,
            main: true,
            tidalUrl: artistResult.attributes.tidalURL,
            popularity: artistResult.attributes.popularityRating
        )
        
        return TidalAlbumResource(
            id: album.data.id,
            barcodeId: album.data.attributes.barcodeId,
            title: album.data.attributes.title ?? "",
            artists: [artist],
            duration: album.data.attributes.durationInSeconds,
            releaseDate: album.data.attributes.releaseDate,
            imageCover: album.data.attributes.tidalImages,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: album.data.attributes.tidalURL,
            properties: nil,
            mediaMetadata: album.data.attributes.mediaTags,
            isExplicit: album.data.attributes.isExplicit,
            popularity: album.data.attributes.popularityRating
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
              let artistResult = albumResult.included.first(where: { $0.type.lowercased().contains("artist") }) else { return [] }
        
        let artist = TidalArtistResource(
            id: artistResult.id,
            name: artistResult.attributes.label,
            picture: artistResult.attributes.tidalImages,
            main: true,
            tidalUrl: artistResult.attributes.tidalURL,
            popularity: artistResult.attributes.popularityRating
        )
        
        let album = TidalAlbumResource(
            id: albumResult.data.id,
            barcodeId: albumResult.data.attributes.barcodeId,
            title: albumResult.data.attributes.title ?? "",
            artists: [artist],
            duration: albumResult.data.attributes.durationInSeconds,
            releaseDate: albumResult.data.attributes.releaseDate,
            imageCover: albumResult.data.attributes.tidalImages,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: albumResult.data.attributes.tidalURL,
            properties: nil,
            mediaMetadata: albumResult.data.attributes.mediaTags,
            isExplicit: albumResult.data.attributes.isExplicit,
            popularity: albumResult.data.attributes.popularityRating
        )
        
        return albumResult.included.map {
            TidalTrackResource(
                id: $0.id,
                isrc: $0.attributes.isrc,
                title: $0.attributes.title ?? "",
                artists: [],
                album: album,
                duration: $0.attributes.durationInSeconds,
                releaseDate: nil,
                imageCover: [],
                numberOfVolumes: nil,
                numberOfTracks: nil,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: "",
                mediaMetadata: nil,
                isExplicit: $0.attributes.isExplicit,
                popularity: $0.attributes.popularityRating
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
              let tracks = result.included else { return [] }
        
        let artist = TidalArtistResource(
            id: result.data.id,
            name: result.data.attributes.label,
            picture: result.data.attributes.tidalImages,
            main: true,
            tidalUrl: result.data.attributes.tidalURL,
            popularity: result.data.attributes.popularityRating
        )
        
        return tracks.compactMap {
            TidalTrackResource(
                id: $0.id,
                isrc: $0.attributes.isrc,
                title: $0.attributes.label,
                artists: [artist],
                album: nil,
                duration: $0.attributes.durationInSeconds,
                releaseDate: $0.attributes.releaseDate,
                imageCover: $0.attributes.tidalImages,
                numberOfVolumes: $0.attributes.numberOfVolumes,
                numberOfTracks: $0.attributes.numberOfItems,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: $0.attributes.tidalURL,
                mediaMetadata: $0.attributes.mediaTags,
                isExplicit: $0.attributes.isExplicit,
                popularity: $0.attributes.popularityRating
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
              let albums = result.included else { return [] }
        
        let artist = TidalArtistResource(
            id: result.data.id,
            name: result.data.attributes.label,
            picture: result.data.attributes.tidalImages,
            main: true,
            tidalUrl: result.data.attributes.tidalURL,
            popularity: result.data.attributes.popularityRating
        )
        
        return albums.compactMap {
            TidalAlbumResource(
                id: $0.id,
                barcodeId: $0.attributes.barcodeId,
                title: $0.attributes.label,
                artists: [artist],
                duration: $0.attributes.durationInSeconds,
                releaseDate: $0.attributes.releaseDate,
                imageCover: $0.attributes.tidalImages,
                numberOfVolumes: $0.attributes.numberOfVolumes,
                numberOfTracks: $0.attributes.numberOfItems,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: $0.attributes.tidalURL,
                properties: nil,
                mediaMetadata: $0.attributes.mediaTags,
                isExplicit: $0.attributes.isExplicit,
                popularity: $0.attributes.popularityRating
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

        guard let result: AlbumResult = try? await loadAuthorized(url) else { return nil }
        
        let artist = TidalArtistResource(
            id: result.data.id,
            name: result.data.attributes.label,
            picture: result.data.attributes.tidalImages,
            main: true,
            tidalUrl: result.data.attributes.tidalURL,
            popularity: result.data.attributes.popularityRating
        )
        
        return artist
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
