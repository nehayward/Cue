import Foundation
import OSLog

public struct LastFMTrack: Sendable {
    public let name: String
    public let playcount: Int
}

public final class LastFMAPI: Sendable {
    private let apiKey = "92fc745ad70e4d226be117d5b7873884"
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "LastFMAPI", category: "LastFMAPI")

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func artistTopTracks(artist: String, limit: Int = 50) async -> [LastFMTrack] {
        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        components.queryItems = [
            URLQueryItem(name: "method", value: "artist.gettoptracks"),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else { return [] }

        guard let (data, _) = try? await session.data(from: url) else { return [] }

        do {
            let response = try decoder.decode(LastFMTopTracksResponse.self, from: data)
            return response.toptracks.track.compactMap { track in
                guard let playcount = Int(track.playcount) else { return nil }
                return LastFMTrack(name: track.name, playcount: playcount)
            }
        } catch {
            logger.error("Failed to decode Last.fm response: \(error)")
            return []
        }
    }
}

private struct LastFMTopTracksResponse: Decodable {
    let toptracks: LastFMTopTracks
}

private struct LastFMTopTracks: Decodable {
    let track: [LastFMTrackItem]
}

private struct LastFMTrackItem: Decodable {
    let name: String
    let playcount: String
}
