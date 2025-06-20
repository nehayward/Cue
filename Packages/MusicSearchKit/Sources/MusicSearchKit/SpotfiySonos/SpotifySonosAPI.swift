import Foundation

public final class SpotifySonosAPI {
    static let shared = SpotifySonosAPI()
    private let baseURL = "https://spotify-v5.ws.sonos.com/smapi"
    private let tokenRefreshHandler: TokenRefreshHandler?
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 0.2
    
    public init(tokenRefreshHandler: TokenRefreshHandler? = nil) {
        self.tokenRefreshHandler = tokenRefreshHandler
    }
    
    // MARK: - Public API Methods
    
    public func refreshTokenIfNeeded(credentials: Credentials? = nil) async throws -> (String, String)? {
        let currentCredentials: Credentials
        if let providedCredentials = credentials {
            currentCredentials = providedCredentials
        } else {
            guard let handler = tokenRefreshHandler else {
                throw SpotifyMetadataError.missingTokenHandler
            }
            
            guard let handlerCredentials = try await handler.getCredentials() else {
                throw SpotifyMetadataError.tokenRefreshFailed
            }
            currentCredentials = handlerCredentials
        }
        
        // Try a simple request to test if the current token is valid
        let testRequest = MetadataRequest(
            deviceId: currentCredentials.deviceId,
            householdId: currentCredentials.householdId,
            token: currentCredentials.token,
            key: currentCredentials.key,
            id: "your_songs",
            index: 0,
            count: 1
        )
        
        do {
            // Make the request directly to check for token refresh
            let request = createRequest(testRequest)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpotifyMetadataError.invalidResponse
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? ""
            
            // Check if token refresh is required
            if responseString.contains("Client.TokenRefreshRequired") {
                let refreshResponse = try parseTokenRefreshResponse(responseString)
                return (refreshResponse.authToken, refreshResponse.privateKey)
            }
            
            // If we get here, the token is still valid
            guard httpResponse.statusCode == 200 else {
                throw SpotifyMetadataError.serverError(httpResponse.statusCode)
            }
            
            return (currentCredentials.token, currentCredentials.key)
            
        } catch {
            // Re-throw any other errors
            throw error
        }
    }
    
    public func getMetadata(
        id: String = "your_songs",
        index: Int = 0,
        count: Int = 50
    ) async throws -> SpotifyMetadataResponse {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        var retryCount = 0
        while retryCount < maxRetries {
            if let credentials = try await handler.getCredentials() {
                let request = MetadataRequest(
                    deviceId: credentials.deviceId,
                    householdId: credentials.householdId,
                    token: credentials.token,
                    key: credentials.key,
                    id: id,
                    index: index,
                    count: count
                )
                
                do {
                    let responseString = try await performRequest(request)
                    return try parseSpotifyTracks(from: responseString)
                } catch {
                    retryCount += 1
                    if retryCount == maxRetries {
                        throw error
                    }
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            } else {
                retryCount += 1
                if retryCount == maxRetries {
                    throw SpotifyMetadataError.tokenRefreshFailed
                }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        throw SpotifyMetadataError.tokenRefreshFailed
    }
    
    public func getPlaylists(
        index: Int = 0,
        count: Int = 25
    ) async throws -> SpotifyPlaylistResponse {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        var retryCount = 0
        while retryCount < maxRetries {
            if let credentials = try await handler.getCredentials() {
                let request = MetadataRequest(
                    deviceId: credentials.deviceId,
                    householdId: credentials.householdId,
                    token: credentials.token,
                    key: credentials.key,
                    id: "playlists",
                    index: index,
                    count: count
                )
                
                do {
                    let responseString = try await performRequest(request)
                    return try parsePlaylists(from: responseString)
                } catch {
                    retryCount += 1
                    if retryCount == maxRetries {
                        throw error
                    }
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            } else {
                retryCount += 1
                if retryCount == maxRetries {
                    throw SpotifyMetadataError.tokenRefreshFailed
                }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        throw SpotifyMetadataError.tokenRefreshFailed
    }
    
    public func getPlaylist(
        id: String,
        index: Int = 0,
        count: Int = 100
    ) async throws -> SpotifySongDetailsResponse {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        guard let credentials = try await handler.getCredentials() else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let request = MetadataRequest(
            deviceId: credentials.deviceId,
            householdId: credentials.householdId,
            token: credentials.token,
            key: credentials.key,
            id: "spotify:playlist:\(id)",
            index: index,
            count: count
        )
        
        let responseString = try await performRequest(request)
        return try parseSongDetails(from: responseString)
    }
    
    public func getAlbums(
        index: Int = 0,
        count: Int = 100
    ) async throws -> SpotifyAlbumResponse {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        guard let credentials = try await handler.getCredentials() else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let request = MetadataRequest(
            deviceId: credentials.deviceId,
            householdId: credentials.householdId,
            token: credentials.token,
            key: credentials.key,
            id: "your_albums",
            index: index,
            count: count
        )
        
        let responseString = try await performRequest(request)
        return try parseAlbums(from: responseString)
    }
    
    public func getAlbum(
        for id: String,
        index: Int = 0,
        count: Int = 100
    ) async throws -> SpotifyAlbumTracksResponse {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        guard let credentials = try await handler.getCredentials() else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let request = MetadataRequest(
            deviceId: credentials.deviceId,
            householdId: credentials.householdId,
            token: credentials.token,
            key: credentials.key,
            id: "spotify:album:\(id)",
            index: index,
            count: count
        )
        
        let responseString = try await performRequest(request)
        return try parseAlbumTracks(from: responseString)
    }
    
    public func getSongDetail(
        songId: String
    ) async throws -> SpotifySongDetails {
        let response = try await getSongDetails(songId: songId, index: 0, count: 1)
        guard let song = response.songs.first else {
            throw SpotifyMetadataError.parsingError
        }
        return song
    }
    
    public func getSongDetails(
        songId: String,
        index: Int = 0,
        count: Int = 100
    ) async throws -> SpotifySongDetailsResponse {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        guard let credentials = try await handler.getCredentials() else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let request = MetadataRequest(
            deviceId: credentials.deviceId,
            householdId: credentials.householdId,
            token: credentials.token,
            key: credentials.key,
            id: "spotify:track:\(songId)",
            index: index,
            count: count
        )
        
        let responseString = try await performRequest(request)
        return try parseSongDetails(from: responseString)
    }
    
    public func getArtist(
        artistId: String,
        index: Int = 0,
        count: Int = 50
    ) async throws -> SpotifyArtistResponse {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        guard let credentials = try await handler.getCredentials() else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let request = MetadataRequest(
            deviceId: credentials.deviceId,
            householdId: credentials.householdId,
            token: credentials.token,
            key: credentials.key,
            id: "spotify:artist:\(artistId)",
            index: index,
            count: count
        )
        
        let responseString = try await performRequest(request)
        return try parseArtist(from: responseString)
    }
    
    public func getArtistTopTracks(
        artistId: String,
        index: Int = 0,
        count: Int = 100
    ) async throws -> SpotifySongDetailsResponse {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        guard let credentials = try await handler.getCredentials() else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let request = MetadataRequest(
            deviceId: credentials.deviceId,
            householdId: credentials.householdId,
            token: credentials.token,
            key: credentials.key,
            id: "spotify:artistTopTracks:\(artistId)",
            index: index,
            count: count
        )
        
        let responseString = try await performRequest(request)
        return try parseSongDetails(from: responseString)
    }
    
    public func favoriteTrack(trackId: String) async throws {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        guard let credentials = try await handler.getCredentials() else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let request = createRateItemRequest(
            deviceId: credentials.deviceId,
            householdId: credentials.householdId,
            token: credentials.token,
            key: credentials.key,
            id: "spotify:track:\(trackId)",
            rating: 1
        )
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyMetadataError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SpotifyMetadataError.serverError(httpResponse.statusCode)
        }
    }
    
    public func unvfavoriteTrack(trackId: String) async throws {
        guard let handler = tokenRefreshHandler else {
            throw SpotifyMetadataError.missingTokenHandler
        }
        
        guard let credentials = try await handler.getCredentials() else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let request = createRateItemRequest(
            deviceId: credentials.deviceId,
            householdId: credentials.householdId,
            token: credentials.token,
            key: credentials.key,
            id: "spotify:track:\(trackId)",
            rating: 0
        )
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyMetadataError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SpotifyMetadataError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Private Methods
    
    struct MetadataRequest {
        let deviceId: String
        let householdId: String
        let token: String
        let key: String
        let id: String
        let index: Int
        let count: Int
    }
    
    private func createRequest(_ metadataRequest: MetadataRequest) -> URLRequest {
        let soapEnvelope = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
            <s:Header>
                <credentials xmlns="http://www.sonos.com/Services/1.1">
                    <deviceId>\(metadataRequest.deviceId)</deviceId>
                    <deviceProvider>Sonos</deviceProvider>
                    <loginToken>
                        <token>\(metadataRequest.token)</token>
                        <key>\(metadataRequest.key)</key>
                        <householdId>\(metadataRequest.householdId)</householdId>
                    </loginToken>
                </credentials>
            </s:Header>
            <s:Body>
                <getMetadata xmlns="http://www.sonos.com/Services/1.1">
                    <id>\(metadataRequest.id)</id>
                    <index>\(metadataRequest.index)</index>
                    <count>\(metadataRequest.count)</count>
                </getMetadata>
            </s:Body>
        </s:Envelope>
        """
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("\"http://www.sonos.com/Services/1.1#getMetadata\"", forHTTPHeaderField: "SOAPACTION")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("Linux UPnP/1.0 Sonos/79.0-52294 (MDCR_MacBookPro16,1)", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US, en-US;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = soapEnvelope.data(using: .utf8)
        
        return request
    }
    
    private func parseTokenRefreshResponse(_ xmlString: String) throws -> SpotifyTokenRefreshResponse {
        let patterns = [
            ("<ns2:authToken>([^<]+)</ns2:authToken>", "authToken"),
            ("<ns2:privateKey>([^<]+)</ns2:privateKey>", "privateKey"),
            ("<ns2:userIdHashCode>([^<]+)</ns2:userIdHashCode>", "userIdHashCode"),
            ("<ns2:accountTier>([^<]+)</ns2:accountTier>", "accountTier"),
            ("<ns2:nickname>([^<]+)</ns2:nickname>", "nickname")
        ]
        
        var values: [String: String] = [:]
        
        for (pattern, key) in patterns {
            guard let range = xmlString.range(of: pattern, options: .regularExpression),
                  let match = xmlString[range].split(separator: ">").last?.split(separator: "<").first else {
                throw SpotifyMetadataError.parsingError
            }
            values[key] = String(match)
        }
        
        guard let authToken = values["authToken"],
              let privateKey = values["privateKey"],
              let userIdHashCode = values["userIdHashCode"],
              let accountTier = values["accountTier"],
              let nickname = values["nickname"] else {
            throw SpotifyMetadataError.parsingError
        }
        
        return SpotifyTokenRefreshResponse(
            authToken: authToken,
            privateKey: privateKey,
            userIdHashCode: userIdHashCode,
            accountTier: accountTier,
            nickname: nickname
        )
    }
    
    private func parseSpotifyTracks(from xmlString: String) throws -> SpotifyMetadataResponse {
        // Extract the mediaMetadata section
        guard let startIndex = xmlString.range(of: "<ns2:mediaMetadata>")?.lowerBound,
              let endIndex = xmlString.range(of: "</ns2:getMetadataResult>", options: .backwards)?.upperBound else {
            throw SpotifyMetadataError.parsingError
        }
        
        // Extract pagination info
        guard let indexStr = extractValue(from: xmlString, pattern: "<ns2:index>([^<]+)</ns2:index>"),
              let countStr = extractValue(from: xmlString, pattern: "<ns2:count>([^<]+)</ns2:count>"),
              let totalStr = extractValue(from: xmlString, pattern: "<ns2:total>([^<]+)</ns2:total>"),
              let index = Int(indexStr),
              let count = Int(countStr),
              let total = Int(totalStr) else {
            throw SpotifyMetadataError.parsingError
        }
        
        let metadataSection = xmlString[startIndex..<endIndex]
        let trackSections = metadataSection.components(separatedBy: "<ns2:mediaMetadata>")
            .filter { !$0.isEmpty }
        
        let tracks = trackSections.compactMap { section -> SpotifyTrack? in
            guard let id = extractValue(from: section, pattern: "<ns2:id>([^<]+)</ns2:id>"),
                  let title = extractValue(from: section, pattern: "<ns2:title>([^<]+)</ns2:title>"),
                  let artist = extractValue(from: section, pattern: "<ns2:artist>([^<]+)</ns2:artist>"),
                  let artistId = extractValue(from: section, pattern: "<ns2:artistId>([^<]+)</ns2:artistId>"),
                  let album = extractValue(from: section, pattern: "<ns2:album>([^<]+)</ns2:album>"),
                  let albumId = extractValue(from: section, pattern: "<ns2:albumId>([^<]+)</ns2:albumId>"),
                  let durationStr = extractValue(from: section, pattern: "<ns2:duration>([^<]+)</ns2:duration>"),
                  let duration = Int(durationStr),
                  let albumArtURI = extractValue(from: section, pattern: "<ns2:albumArtURI>([^<]+)</ns2:albumArtURI>"),
                  let explicitStr = extractValue(from: section, pattern: "<ns2:explicit>([^<]+)</ns2:explicit>"),
                  let canPlayStr = extractValue(from: section, pattern: "<ns2:canPlay>([^<]+)</ns2:canPlay>"),
                  let canSkipStr = extractValue(from: section, pattern: "<ns2:canSkip>([^<]+)</ns2:canSkip>"),
                  let canAddToFavoritesStr = extractValue(from: section, pattern: "<ns2:canAddToFavorites>([^<]+)</ns2:canAddToFavorites>") else {
                return nil
            }
            
            return SpotifyTrack(
                id: id,
                title: title,
                artist: artist,
                artistId: artistId,
                album: album,
                albumId: albumId,
                duration: duration,
                albumArtURI: albumArtURI,
                isExplicit: explicitStr == "1",
                canPlay: canPlayStr == "true",
                canSkip: canSkipStr == "true",
                canAddToFavorites: canAddToFavoritesStr == "true"
            )
        }
        
        return SpotifyMetadataResponse(
            tracks: tracks,
            index: index,
            count: count,
            total: total
        )
    }
    
    private func parsePlaylists(from xmlString: String) throws -> SpotifyPlaylistResponse {
        // Extract pagination info
        guard let indexStr = extractValue(from: xmlString, pattern: "<ns2:index>([^<]+)</ns2:index>"),
              let countStr = extractValue(from: xmlString, pattern: "<ns2:count>([^<]+)</ns2:count>"),
              let totalStr = extractValue(from: xmlString, pattern: "<ns2:total>([^<]+)</ns2:total>"),
              let index = Int(indexStr),
              let count = Int(countStr),
              let total = Int(totalStr) else {
            throw SpotifyMetadataError.parsingError
        }
        
        let playlistSections = xmlString.components(separatedBy: "<ns2:mediaCollection")
            .filter { $0.contains("itemType>playlist</ns2:itemType>") }
        
        let playlists = playlistSections.compactMap { section -> SpotifyPlaylist? in
            guard let id = extractValue(from: section, pattern: "<ns2:id>([^<]+)</ns2:id>"),
                  let title = extractValue(from: section, pattern: "<ns2:title>([^<]+)</ns2:title>"),
                  let artist = extractValue(from: section, pattern: "<ns2:artist>([^<]+)</ns2:artist>"),
                  let albumArtURI = extractValue(from: section, pattern: "<ns2:albumArtURI>([^<]+)</ns2:albumArtURI>"),
                  let canPlayStr = extractValue(from: section, pattern: "<ns2:canPlay>([^<]+)</ns2:canPlay>"),
                  let canEnumerateStr = extractValue(from: section, pattern: "<ns2:canEnumerate>([^<]+)</ns2:canEnumerate>") else {
                return nil
            }
            
            return SpotifyPlaylist(
                id: id,
                title: title,
                description: nil,
                albumArtURI: albumArtURI,
                canPlay: canPlayStr == "true",
                canAddToFavorites: false
            )
        }
        
        return SpotifyPlaylistResponse(
            playlists: playlists,
            index: index,
            count: count,
            total: total
        )
    }
    
    private func parseAlbums(from xmlString: String) throws -> SpotifyAlbumResponse {
        // Extract pagination info
        guard let indexStr = extractValue(from: xmlString, pattern: "<ns2:index>([^<]+)</ns2:index>"),
              let countStr = extractValue(from: xmlString, pattern: "<ns2:count>([^<]+)</ns2:count>"),
              let totalStr = extractValue(from: xmlString, pattern: "<ns2:total>([^<]+)</ns2:total>"),
              let index = Int(indexStr),
              let count = Int(countStr),
              let total = Int(totalStr) else {
            throw SpotifyMetadataError.parsingError
        }
        
        let albumSections = xmlString.components(separatedBy: "<ns2:mediaCollection")
            .filter { $0.contains("itemType>album</ns2:itemType>") }
        
        let albums = albumSections.compactMap { section -> SpotifyAlbum? in
            guard let id = extractValue(from: section, pattern: "<ns2:id>([^<]+)</ns2:id>"),
                  let title = extractValue(from: section, pattern: "<ns2:title>([^<]+)</ns2:title>"),
                  let artist = extractValue(from: section, pattern: "<ns2:artist>([^<]+)</ns2:artist>"),
                  let artistId = extractValue(from: section, pattern: "<ns2:artistId>([^<]+)</ns2:artistId>"),
                  let albumArtURI = extractValue(from: section, pattern: "<ns2:albumArtURI>([^<]+)</ns2:albumArtURI>"),
                  let canPlayStr = extractValue(from: section, pattern: "<ns2:canPlay>([^<]+)</ns2:canPlay>"),
                  let canEnumerateStr = extractValue(from: section, pattern: "<ns2:canEnumerate>([^<]+)</ns2:canEnumerate>") else {
                return nil
            }
            
            return SpotifyAlbum(
                id: id,
                title: title,
                artist: artist,
                artistId: artistId,
                albumArtURI: albumArtURI,
                canPlay: canPlayStr == "true",
                canEnumerate: canEnumerateStr == "true"
            )
        }
        
        return SpotifyAlbumResponse(
            albums: albums,
            index: index,
            count: count,
            total: total
        )
    }
    
    private func parseSongDetails(from xmlString: String) throws -> SpotifySongDetailsResponse {
        // Extract pagination info
        guard let indexStr = extractValue(from: xmlString, pattern: "<ns2:index>([^<]+)</ns2:index>"),
              let countStr = extractValue(from: xmlString, pattern: "<ns2:count>([^<]+)</ns2:count>"),
              let totalStr = extractValue(from: xmlString, pattern: "<ns2:total>([^<]+)</ns2:total>"),
              let index = Int(indexStr),
              let count = Int(countStr),
              let total = Int(totalStr) else {
            throw SpotifyMetadataError.parsingError
        }
        
        let songSections = xmlString.components(separatedBy: "<ns2:mediaMetadata")
            .filter { $0.contains("itemType>track</ns2:itemType>") }
        let songs = songSections.compactMap { section -> SpotifySongDetails? in
            guard let id = extractValue(from: section, pattern: "<ns2:id>([^<]+)</ns2:id>"),
                  let title = extractValue(from: section, pattern: "<ns2:title>([^<]+)</ns2:title>"),
                  let artist = extractValue(from: section, pattern: "<ns2:artist>([^<]+)</ns2:artist>"),
                  let artistId = extractValue(from: section, pattern: "<ns2:artistId>([^<]+)</ns2:artistId>"),
                  let album = extractValue(from: section, pattern: "<ns2:album>([^<]+)</ns2:album>"),
                  let albumId = extractValue(from: section, pattern: "<ns2:albumId>([^<]+)</ns2:albumId>"),
                  let durationStr = extractValue(from: section, pattern: "<ns2:duration>([^<]+)</ns2:duration>"),
                  let duration = Int(durationStr),
                  let albumArtURI = extractValue(from: section, pattern: "<ns2:albumArtURI>([^<]+)</ns2:albumArtURI>"),
                  let explicitStr = extractValue(from: section, pattern: "<ns2:tags>\\s*<ns2:explicit>([^<]+)</ns2:explicit>"),
                  let canPlayStr = extractValue(from: section, pattern: "<ns2:canPlay>([^<]+)</ns2:canPlay>"),
                  let canSkipStr = extractValue(from: section, pattern: "<ns2:canSkip>([^<]+)</ns2:canSkip>"),
                  let canAddToFavoritesStr = extractValue(from: section, pattern: "<ns2:canAddToFavorites>([^<]+)</ns2:canAddToFavorites>") else {
                return nil
            }
            
            return SpotifySongDetails(
                id: id,
                title: title,
                artist: artist,
                artistId: artistId,
                album: album,
                albumId: albumId,
                duration: duration,
                albumArtURI: albumArtURI,
                isExplicit: explicitStr == "1",
                canPlay: canPlayStr == "true",
                canSkip: canSkipStr == "true",
                canAddToFavorites: canAddToFavoritesStr == "true"
            )
        }
        
        return SpotifySongDetailsResponse(
            songs: songs,
            index: index,
            count: count,
            total: total
        )
    }
    
    private func parseArtist(from xmlString: String) throws -> SpotifyArtistResponse {
        // Extract pagination info
        guard let indexStr = extractValue(from: xmlString, pattern: "<ns2:index>([^<]+)</ns2:index>"),
              let countStr = extractValue(from: xmlString, pattern: "<ns2:count>([^<]+)</ns2:count>"),
              let totalStr = extractValue(from: xmlString, pattern: "<ns2:total>([^<]+)</ns2:total>"),
              let index = Int(indexStr),
              let count = Int(countStr),
              let total = Int(totalStr) else {
            throw SpotifyMetadataError.parsingError
        }
        
        let mediaCollections = xmlString.components(separatedBy: "<ns2:mediaCollection")
            .filter { !$0.isEmpty }
        
        let artists = mediaCollections.compactMap { section -> SpotifyArtist? in
            guard let id = extractValue(from: section, pattern: "<ns2:id>([^<]+)</ns2:id>"),
                  let itemType = extractValue(from: section, pattern: "<ns2:itemType>([^<]+)</ns2:itemType>"),
                  let title = extractValue(from: section, pattern: "<ns2:title>([^<]+)</ns2:title>"),
                  let albumArtURI = extractValue(from: section, pattern: "<ns2:albumArtURI>([^<]+)</ns2:albumArtURI>"),
                  let canPlayStr = extractValue(from: section, pattern: "<ns2:canPlay>([^<]+)</ns2:canPlay>"),
                  let canEnumerateStr = extractValue(from: section, pattern: "<ns2:canEnumerate>([^<]+)</ns2:canEnumerate>") else {
                return nil
            }
            
            // Get optional fields
            let artist = extractValue(from: section, pattern: "<ns2:artist>([^<]+)</ns2:artist>")
            let artistId = extractValue(from: section, pattern: "<ns2:artistId>([^<]+)</ns2:artistId>")
            let displayType = extractValue(from: section, pattern: "<ns2:displayType>([^<]+)</ns2:displayType>")
            
            return SpotifyArtist(
                id: id,
                name: title,
                artist: artist,
                artistId: artistId,
                itemType: itemType,
                displayType: displayType,
                albumArtURI: albumArtURI,
                canPlay: canPlayStr == "true",
                canEnumerate: canEnumerateStr == "true"
            )
        }
        
        return SpotifyArtistResponse(
            artists: artists,
            index: index,
            count: count,
            total: total
        )
    }
    
    func extractValue(from string: String, pattern: String) -> String? {
        guard let range = string.range(of: pattern, options: .regularExpression),
              let match = string[range].split(separator: ">").last?.split(separator: "<").first else {
            return nil
        }
        return String(match)
    }
    
    private func performRequest(_ metadataRequest: MetadataRequest) async throws -> String {
        let request = createRequest(metadataRequest)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyMetadataError.invalidResponse
        }
        
        let responseString = String(data: data, encoding: .utf8) ?? ""
        
        if responseString.contains("Client.TokenRefreshRequired") {
            // Use the unified coordinator to prevent race conditions
            let credentials = Credentials(
                deviceId: metadataRequest.deviceId,
                householdId: metadataRequest.householdId,
                token: metadataRequest.token,
                key: metadataRequest.key
            )
            
            guard let (token, key) = try await TokenRefreshCoordinator.shared.refreshToken(credentials: credentials) else {
                throw SpotifyMetadataError.tokenRefreshFailed
            }
            
            try await tokenRefreshHandler?.handleTokenRefresh(householdId: metadataRequest.householdId, token: token, key: key)
            
            // Retry with new tokens
            let newRequest = MetadataRequest(
                deviceId: metadataRequest.deviceId,
                householdId: metadataRequest.householdId,
                token: token,
                key: key,
                id: metadataRequest.id,
                index: metadataRequest.index,
                count: metadataRequest.count
            )
            return try await performRequest(newRequest)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SpotifyMetadataError.serverError(httpResponse.statusCode)
        }
        
        return responseString
    }
    
    private func parseAlbumTracks(from xmlString: String) throws -> SpotifyAlbumTracksResponse {
        // Extract pagination info
        guard let indexStr = extractValue(from: xmlString, pattern: "<ns2:index>([^<]+)</ns2:index>"),
              let countStr = extractValue(from: xmlString, pattern: "<ns2:count>([^<]+)</ns2:count>"),
              let totalStr = extractValue(from: xmlString, pattern: "<ns2:total>([^<]+)</ns2:total>"),
              let index = Int(indexStr),
              let count = Int(countStr),
              let total = Int(totalStr) else {
            throw SpotifyMetadataError.parsingError
        }
        
        let trackSections = xmlString.components(separatedBy: "<ns2:mediaMetadata")
            .filter { $0.contains("itemType>track</ns2:itemType>") }
        
        let tracks = trackSections.compactMap { section -> SpotifyAlbumTrack? in
            guard let id = extractValue(from: section, pattern: "<ns2:id>([^<]+)</ns2:id>"),
                  let title = extractValue(from: section, pattern: "<ns2:title>([^<]+)</ns2:title>"),
                  let artist = extractValue(from: section, pattern: "<ns2:artist>([^<]+)</ns2:artist>"),
                  let artistId = extractValue(from: section, pattern: "<ns2:artistId>([^<]+)</ns2:artistId>"),
                  let album = extractValue(from: section, pattern: "<ns2:album>([^<]+)</ns2:album>"),
                  let albumId = extractValue(from: section, pattern: "<ns2:albumId>([^<]+)</ns2:albumId>"),
                  let durationStr = extractValue(from: section, pattern: "<ns2:duration>([^<]+)</ns2:duration>"),
                  let duration = Int(durationStr),
                  let albumArtURI = extractValue(from: section, pattern: "<ns2:albumArtURI>([^<]+)</ns2:albumArtURI>"),
                  let trackNumberStr = extractValue(from: section, pattern: "<ns2:trackNumber>([^<]+)</ns2:trackNumber>"),
                  let trackNumber = Int(trackNumberStr),
                  let explicitStr = extractValue(from: section, pattern: "<ns2:explicit>([^<]+)</ns2:explicit>"),
                  let canPlayStr = extractValue(from: section, pattern: "<ns2:canPlay>([^<]+)</ns2:canPlay>"),
                  let canSkipStr = extractValue(from: section, pattern: "<ns2:canSkip>([^<]+)</ns2:canSkip>"),
                  let canAddToFavoritesStr = extractValue(from: section, pattern: "<ns2:canAddToFavorites>([^<]+)</ns2:canAddToFavorites>") else {
                return nil
            }
            
            return SpotifyAlbumTrack(
                id: id,
                title: title,
                artist: artist,
                artistId: artistId,
                album: album,
                albumId: albumId,
                duration: duration,
                albumArtURI: albumArtURI,
                trackNumber: trackNumber,
                isExplicit: explicitStr == "1",
                canPlay: canPlayStr == "true",
                canSkip: canSkipStr == "true",
                canAddToFavorites: canAddToFavoritesStr == "true"
            )
        }
        
        return SpotifyAlbumTracksResponse(
            tracks: tracks,
            index: index,
            count: count,
            total: total
        )
    }
    
    private func createRateItemRequest(
        deviceId: String,
        householdId: String,
        token: String,
        key: String,
        id: String,
        rating: Int
    ) -> URLRequest {
        let soapEnvelope = """
        <Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="http://schemas.xmlsoap.org/soap/envelope/">
          <Header>
            <credentials xmlns="http://www.sonos.com/Services/1.1">
              <loginToken>
                <token>\(token)</token>
                <key>\(key)</key>
                <householdId>\(householdId)</householdId>
              </loginToken>
            </credentials>
            <context xmlns="http://www.sonos.com/Services/1.1">
              <timeZone>00:00</timeZone>
            </context>
          </Header>
          <Body>
            <rateItem xmlns="http://www.sonos.com/Services/1.1">
              <id>\(id)</id>
              <rating>\(rating)</rating>
            </rateItem>
          </Body>
        </Envelope>
        """
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("\"http://www.sonos.com/Services/1.1#rateItem\"", forHTTPHeaderField: "SOAPACTION")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("Linux UPnP/1.0 Sonos/79.0-52294 (MDCR_MacBookPro16,1)", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US, en-US;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = soapEnvelope.data(using: .utf8)
        
        return request
    }
}
