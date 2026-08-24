import Foundation
import MusicKit
import MusicSearchKit
import SonosKit

final class PopularTracksService {
    static let shared = PopularTracksService()

    private let lastFM = LastFMAPI()

    func matchLastFM(artistName: String, songs: [PlayableContent]) async -> [PlayableContent] {
        let tracks = await lastFM.artistTopTracks(artist: artistName, limit: 50)
        return match(tracks.map(\.name), against: songs)
    }

    func matchAppleMusic(artistName: String, songs: [PlayableContent]) async -> [PlayableContent] {
        guard let authorization = try? await MusicAuthorization.request(), authorization == .authorized else { return [] }
        var searchRequest = MusicCatalogSearchRequest(term: artistName, types: [Artist.self])
        searchRequest.limit = 1
        guard let searchResponse = try? await searchRequest.response(),
              let artist = searchResponse.artists.first else { return [] }

        var catalogResource = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: artist.id)
        catalogResource.properties = [.topSongs]
        guard let response = try? await catalogResource.response(),
              let artistWithSongs = response.items.first,
              let topSongs = artistWithSongs.topSongs else { return [] }

        return match(topSongs.map(\.title), against: songs)
    }

    func match(_ titles: [String], against songs: [PlayableContent]) -> [PlayableContent] {
        let byTitle = Dictionary(
            songs.map { (normalize($0.title), $0) },
            uniquingKeysWith: { $0.title.count <= $1.title.count ? $0 : $1 }
        )
        var matched: [PlayableContent] = []
        var matchedIDs: Set<String> = []
        for title in titles {
            let norm = normalize(title)
            if let song = byTitle[norm], !matchedIDs.contains(song.id) {
                matched.append(song)
                matchedIDs.insert(song.id)
            } else {
                let words = norm.split(separator: " ")
                if let song = songs.first(where: {
                    !matchedIDs.contains($0.id) &&
                    normalize($0.title).split(separator: " ").starts(with: words)
                }) {
                    matched.append(song)
                    matchedIDs.insert(song.id)
                }
            }
            if matched.count >= 10 { break }
        }
        return matched
    }

    private func normalize(_ title: String) -> String {
        var s = title.lowercased()
        let patterns = [
            "\\s*\\([^)]*\\)",
            "\\s*\\[[^]]*\\]",
            "\\s*-\\s*(remaster|live|deluxe|bonus|edit|remix|version|mono|stereo).*$",
            "\\s+(?:feat\\.?|featuring|ft\\.?)\\s+.+$"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
            }
        }
        s = String(s.unicodeScalars.filter { CharacterSet.alphanumerics.union(.whitespaces).contains($0) })
        return s.split(separator: " ").joined(separator: " ")
    }
}
