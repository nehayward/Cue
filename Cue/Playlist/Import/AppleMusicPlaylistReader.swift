import Foundation
import MusicKit
import MusicSearchKit
import SonosKit

/// Reads an Apple Music playlist or album for importing: a catalog playlist
/// or album through MusicKit, and one of the user's own library playlists
/// through the web API, which is where `p.…` ids live. Each song keeps its
/// ISRC, so matching it on another service can be exact.
@MainActor
enum AppleMusicPlaylistReader {
    static func read(_ link: PlaylistLink) async throws -> ImportedPlaylist {
        guard await MusicSearchService.shared.requestMusicAuthorization() else {
            throw PlaylistImportError.appleMusicNotAuthorized
        }
        switch link {
        case let .appleMusic(.playlist, id, _):
            return try await catalogPlaylist(id: id)
        case let .appleMusic(.album, id, _):
            return try await catalogAlbum(id: id)
        case let .appleMusicLibrary(id):
            return try await libraryPlaylist(id: id, name: nil)
        default:
            throw PlaylistImportError.unsupported
        }
    }

    /// One of the user's own playlists, as the library lists them.
    static func read(libraryPlaylist playlist: PlayableContent) async throws -> ImportedPlaylist {
        guard await MusicSearchService.shared.requestMusicAuthorization() else {
            throw PlaylistImportError.appleMusicNotAuthorized
        }
        return try await libraryPlaylist(id: playlist.content.id, name: playlist.title)
    }

    // MARK: - Catalog

    private static func catalogPlaylist(id: String) async throws -> ImportedPlaylist {
        var request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
        request.properties = [.tracks]
        let playlist: Playlist
        do {
            guard let found = try await request.response().items.first else { throw PlaylistImportError.notFound }
            playlist = found
        } catch let error as PlaylistImportError {
            throw error
        } catch {
            throw PlaylistImportError.unreachable
        }
        let tracks = try await allTracks(from: playlist.tracks)
        guard !tracks.isEmpty else { throw PlaylistImportError.empty }
        return ImportedPlaylist(
            name: playlist.name,
            source: .appleMusic,
            artwork: playlist.artwork?.url(width: 600, height: 600),
            tracks: imported(tracks)
        )
    }

    private static func catalogAlbum(id: String) async throws -> ImportedPlaylist {
        var request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
        request.properties = [.tracks]
        let album: Album
        do {
            guard let found = try await request.response().items.first else { throw PlaylistImportError.notFound }
            album = found
        } catch let error as PlaylistImportError {
            throw error
        } catch {
            throw PlaylistImportError.unreachable
        }
        let tracks = try await allTracks(from: album.tracks)
        guard !tracks.isEmpty else { throw PlaylistImportError.empty }
        return ImportedPlaylist(
            name: album.title,
            source: .appleMusic,
            artwork: album.artwork?.url(width: 600, height: 600),
            tracks: imported(tracks)
        )
    }

    /// Every page of a playlist's or album's songs; a long playlist arrives
    /// a hundred at a time.
    private static func allTracks(from first: MusicItemCollection<MusicKit.Track>?) async throws -> [MusicKit.Track] {
        guard var page = first else { return [] }
        var tracks = Array(page)
        while page.hasNextBatch {
            guard let next = try? await page.nextBatch() else { break }
            tracks += next
            page = next
        }
        return tracks
    }

    private static func imported(_ tracks: [MusicKit.Track]) -> [ImportedTrack] {
        tracks.enumerated().map { index, track in
            ImportedTrack(
                id: index,
                title: track.title,
                artists: [track.artistName],
                album: track.albumTitle,
                duration: track.duration,
                isrc: track.isrc,
                sourceID: track.id.rawValue
            )
        }
    }

    // MARK: - Library

    private static func libraryPlaylist(id: String, name: String?) async throws -> ImportedPlaylist {
        let apple = AppleMusicAPI.shared
        var items: [AppleLibraryItem] = []
        var total: Int?
        // The web API pages a library playlist by offset; it answers an
        // offset past the end with nothing.
        while total.map({ items.count < $0 }) ?? true {
            guard let page = try? await apple.lookupUsersLibraryPlaylist(id: id, offset: items.count) else {
                if items.isEmpty { throw PlaylistImportError.unreachable }
                break
            }
            total = page.meta?.total ?? total
            if page.data.isEmpty { break }
            items += page.data
            if page.next == nil { break }
        }
        guard !items.isEmpty else { throw PlaylistImportError.empty }

        var playlistName = name
        var artwork: URL?
        if let header = try? await apple.getUserPlaylist(with: id)?.data.first {
            playlistName = playlistName ?? header.attributes.name
            artwork = header.attributes.artwork?.urlWithSize(width: 600, height: 600)
        }

        let tracks = items.enumerated().compactMap { index, item -> ImportedTrack? in
            let attributes = item.attributes
            let catalog = item.relationships?.catalog?.data.first
            guard let title = attributes.name ?? catalog?.attributes.name else { return nil }
            return ImportedTrack(
                id: index,
                title: title,
                artists: [attributes.artistName ?? catalog?.attributes.artistName].compactMap { $0 },
                album: attributes.albumName ?? catalog?.attributes.albumName,
                duration: (attributes.durationInMillis ?? catalog?.attributes.durationInMillis).map { Double($0) / 1000 },
                isrc: attributes.isrc ?? catalog?.attributes.isrc,
                sourceID: catalog?.id ?? item.id
            )
        }
        return ImportedPlaylist(
            name: playlistName ?? "Apple Music Playlist",
            source: .appleMusic,
            artwork: artwork,
            tracks: tracks,
            totalCount: total
        )
    }
}
