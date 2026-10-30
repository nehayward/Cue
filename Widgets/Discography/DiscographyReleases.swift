import AppIntents
import Defaults
import Foundation

/// Which of an artist's releases a discography widget shows: their albums,
/// as the artist page's Albums lists them, or everything.
enum DiscographyReleases: String, AppEnum, CaseIterable {
    case studioAlbums
    case everything

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let caseDisplayRepresentations: [DiscographyReleases: DisplayRepresentation] = [
        .studioAlbums: DisplayRepresentation(title: "Albums", subtitle: "Each album once, in the year it came out"),
        .everything: DisplayRepresentation(title: "All Releases", subtitle: "With EPs, live albums, compilations and reissues"),
    ]
}

extension DiscographyArtist {
    /// What All Releases shows, newest first: an Apple Music artist's
    /// releases without remix albums, and one of each title put out twice
    /// the same day (kept, as Apple's album list can name either).
    func everyRelease() -> [Release] {
        guard id.hasPrefix(AppleMusicArtists.prefix) else { return releases }
        var seen: Set<String> = []
        return releases.filter { release in
            let day = release.released.map { Int($0.timeIntervalSince1970 / 86400) } ?? 0
            return release.title.range(of: "remix", options: .caseInsensitive) == nil
                && seen.insert("\(release.title.lowercased())|\(day)").inserted
        }
    }

    /// The artist's albums, each once, newest first (`AlbumEditions`):
    /// Apple's own list of them where Cue has written one (`listed`, the
    /// Albums shelf in Music), else as the titles say. A Plex artist's are
    /// Plex's Albums already, as the artist page lists them.
    func studioAlbums(listedBy listed: Set<String>?) -> [Release] {
        let listed = listed.flatMap { $0.isEmpty ? nil : $0 }
        let candidates = listed.map { listed in releases.filter { listed.contains($0.id) } } ?? releases
        let byTitle = listed == nil && !id.hasPrefix(DiscographyService.plex.prefix)
        return AlbumEditions.albums(candidates, editions: releases, byTitle: byTitle, title: \.title, released: \.released)
            .map { album in
                var release = album.item
                release.title = album.title
                release.released = album.released
                return release
            }
    }
}
