import Foundation
import MusicSearchKit
import WatchSync

/// Browses and searches the Plex and Subsonic servers from the watch, with
/// MusicSearchKit and the sign-ins the iPhone shared (`WatchAccounts`), and
/// looks up the songs of a pick (`songs(for:)`) — whichever device picked
/// it. No iPhone needed: the requests go from the watch to the server, over
/// Wi‑Fi or cellular, or through the iPhone when it's connected over
/// Bluetooth.
///
/// Everything carries the ids the iPhone's library gives the same things (a
/// Plex item's Sonos-style id, a Subsonic id), so keys match (`WatchKeys`):
/// an album picked on either device is the same pick, and a song in it the
/// same file.
@MainActor
final class WatchLibraryBrowser {
    static let shared = WatchLibraryBrowser()

    private struct Listing {
        var items: [WatchBrowseItem] = []
        var isComplete = false
    }

    /// What a list has fetched, kept while it's paged through and fetched
    /// afresh when it starts at the top.
    private var listings: [WatchBrowsePath: Listing] = [:]

    private init() {}

    // MARK: - Pages

    func page(_ path: WatchBrowsePath, offset: Int) async -> WatchBrowsePage {
        let accounts = WatchAccounts.shared
        switch path {
        case .root:
            var sources: [WatchBrowseItem] = []
            if accounts.hasPlex {
                sources.append(WatchBrowseItem(id: "plex", title: WatchSource.plex.title, symbol: "server.rack", destination: .source(.plex)))
            }
            if accounts.hasSubsonic {
                sources.append(WatchBrowseItem(id: "subsonic", title: WatchSource.subsonic.title, symbol: "externaldrive.connected.to.line.below", destination: .source(.subsonic)))
            }
            return WatchBrowsePage(
                title: "Add Music",
                items: sources,
                message: sources.isEmpty ? "Open Cue on your iPhone, signed in to Plex or Subsonic, to share its sign-ins with this watch." : nil
            )

        case let .source(source):
            return WatchBrowsePage(
                title: source.title,
                items: WatchBrowseSection.allCases.map {
                    WatchBrowseItem(id: $0.rawValue, title: $0.title, symbol: $0.symbol, destination: .section(source, $0))
                }
            )

        case .section, .artist, .search:
            if offset == 0 {
                listings[path] = nil
            }
            var listing = listings[path] ?? Listing()
            // Bounded: a source that ignored `offset` and kept answering
            // with new rows would otherwise never stop.
            var rounds = 0
            while listing.items.count < offset + WatchBrowsePage.pageSize, !listing.isComplete, rounds < 20 {
                rounds += 1
                let known = Set(listing.items.map(\.id))
                let fresh = await fetch(path, offset: listing.items.count).filter { !known.contains($0.id) }
                if fresh.isEmpty {
                    listing.isComplete = true
                } else {
                    listing.items += fresh
                }
            }
            listings[path] = listing

            let slice = Array(listing.items.dropFirst(offset).prefix(WatchBrowsePage.pageSize))
            let next = offset + slice.count
            let hasMore = !slice.isEmpty && (next < listing.items.count || !listing.isComplete)
            return WatchBrowsePage(
                title: title(of: path),
                items: slice,
                nextOffset: hasMore ? next : nil,
                container: container(of: path),
                message: listing.items.isEmpty ? emptyMessage(for: path) : nil
            )
        }
    }

    /// One page of a list from the server. Lists that come whole answer at
    /// offset 0 only.
    private func fetch(_ path: WatchBrowsePath, offset: Int) async -> [WatchBrowseItem] {
        let plex = PlexAPI.shared
        let subsonic = SubsonicAPI.shared
        let size = 50
        switch path {
        case .section(.plex, .playlists):
            guard offset == 0 else { return [] }
            return await plex.playlists().compactMap { playlist in
                item(.plex, .playlist, id: playlist.sonosID, title: playlist.title, subtitle: songCount(playlist.leafCount), artwork: plexThumbnail(playlist.thumbImageURL))
            }
        case .section(.plex, .recentlyAdded):
            return await plex.albums(sort: .recentlyAdded, offset: offset, limit: size).compactMap(plexAlbumItem)
        case .section(.plex, .albums):
            return await plex.albums(offset: offset, limit: size).compactMap(plexAlbumItem)
        case .section(.plex, .artists):
            return await plex.artists(offset: offset, limit: size).compactMap { artist in
                item(.plex, .artist, id: artist.sonosID, title: artist.title, artwork: plexThumbnail(artist.thumbImageURL))
            }
        case .section(.plex, .songs):
            return await plex.songPage(offset: offset, limit: size).songs.compactMap(plexSong).map(songItem)

        case .section(.subsonic, .playlists):
            guard offset == 0 else { return [] }
            return await subsonic.playlists().compactMap { playlist in
                let subtitle = [playlist.owner ?? "", songCount(playlist.songCount)].filter { !$0.isEmpty }.joined(separator: " • ")
                return item(.subsonic, .playlist, id: playlist.id, title: playlist.name ?? "", subtitle: subtitle, artwork: SubsonicAPI.coverArtURL(for: playlist.coverArt, size: 300))
            }
        case .section(.subsonic, .recentlyAdded):
            return await subsonic.albumList(type: SubsonicAlbumSort.recentlyAdded.apiType, size: size, offset: offset).compactMap(subsonicAlbumItem)
        case .section(.subsonic, .albums):
            return await subsonic.albumList(type: SubsonicAlbumSort.title.apiType, size: size, offset: offset).compactMap(subsonicAlbumItem)
        case .section(.subsonic, .artists):
            guard offset == 0 else { return [] }
            return await subsonic.artists().compactMap { artist in
                item(.subsonic, .artist, id: artist.id, title: artist.name ?? "", artwork: SubsonicAPI.coverArtURL(for: artist.coverArt, size: 300))
            }
        case .section(.subsonic, .songs):
            return await subsonic.songs(size: size, offset: offset).compactMap(subsonicSong).map(songItem)

        case let .artist(artist):
            guard offset == 0 else { return [] }
            // Newest first to browse; `songs(for:)` takes them oldest first.
            return (await albums(of: artist) ?? []).reversed().map { $0.item }

        case let .search(source, query):
            guard offset == 0 else { return [] }
            return await search(source, for: query)

        case .root, .source:
            return []
        }
    }

    /// Artists, albums, playlists and songs matching `query`, in that order.
    private func search(_ source: WatchSource, for query: String) async -> [WatchBrowseItem] {
        switch source {
        case .plex:
            guard let results = await PlexAPI.shared.search(for: query, limit: 20) else { return [] }
            let artists = results.artists.compactMap { artist in
                item(.plex, .artist, id: artist.id, title: artist.name, artwork: plexThumbnail(artist.imageURL))
            }
            let albums = results.album.compactMap { album in
                item(.plex, .album, id: album.id, title: album.title, subtitle: [album.artist, album.year].filter { !$0.isEmpty }.joined(separator: " • "), artwork: plexThumbnail(album.imageURL))
            }
            let playlists = results.playlists.compactMap { playlist in
                item(.plex, .playlist, id: playlist.id, title: playlist.title, artwork: plexThumbnail(playlist.imageURL))
            }
            // Search doesn't carry a song's file; it's looked up when the
            // song is added.
            let songs = results.tracks.compactMap { track in
                item(.plex, .song, id: track.id, title: track.title, subtitle: track.artist, artwork: plexThumbnail(track.imageURL))
            }
            return artists + albums + playlists + songs
        case .subsonic:
            guard let results = await SubsonicAPI.shared.search(query: query, songCount: 20, albumCount: 10, artistCount: 5) else { return [] }
            let artists = (results.artist ?? []).compactMap { artist in
                item(.subsonic, .artist, id: artist.id, title: artist.name ?? "", artwork: SubsonicAPI.coverArtURL(for: artist.coverArt, size: 300))
            }
            let albums = (results.album ?? []).compactMap(subsonicAlbumItem)
            let songs = (results.song ?? []).compactMap(subsonicSong).map(songItem)
            return artists + albums + songs
        }
    }

    private func title(of path: WatchBrowsePath) -> String {
        switch path {
        case .root: "Add Music"
        case let .source(source): source.title
        case let .section(_, section): section.title
        case let .artist(artist): artist.title
        case let .search(_, query): "“\(query)”"
        }
    }

    private func emptyMessage(for path: WatchBrowsePath) -> String {
        if case .search = path {
            return "No results, or the server can't be reached."
        }
        return "Nothing here, or the server can't be reached."
    }

    /// An artist's page offers the artist whole.
    private func container(of path: WatchBrowsePath) -> WatchBrowseItem? {
        guard case let .artist(artist) = path else { return nil }
        return WatchBrowseItem(id: artist.key, title: artist.title, subtitle: artist.subtitle, artworkURL: artist.artworkURL, pick: artist)
    }

    // MARK: - Rows

    /// A row for an album, playlist, artist or song, carrying the pick that
    /// puts it on the watch. An artist opens on its albums.
    private func item(_ source: WatchSource, _ kind: WatchPick.Kind, id: String?, title: String, subtitle: String = "", artwork: URL?) -> WatchBrowseItem? {
        guard let id, !id.isEmpty else { return nil }
        let pick = WatchPick(source: source, kind: kind, id: id, title: title, subtitle: subtitle, artworkURL: artwork)
        return WatchBrowseItem(
            id: pick.key,
            title: title,
            subtitle: subtitle,
            artworkURL: artwork,
            destination: kind == .artist ? .artist(pick) : nil,
            pick: pick
        )
    }

    private func songItem(_ song: WatchSong) -> WatchBrowseItem {
        WatchBrowseItem(
            id: song.pick.key,
            title: song.title,
            subtitle: song.artist,
            artworkURL: song.artworkURL,
            pick: song.pick,
            song: song
        )
    }

    private func plexAlbumItem(_ album: PlexAlbumItem) -> WatchBrowseItem? {
        let subtitle = [album.parentTitle, album.year.map(String.init)].compactMap { $0 }.joined(separator: " • ")
        return item(.plex, .album, id: album.sonosID, title: album.title ?? "", subtitle: subtitle, artwork: plexThumbnail(album.thumbImageURL))
    }

    private func subsonicAlbumItem(_ album: SubsonicAlbum) -> WatchBrowseItem? {
        let subtitle = [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " • ")
        return item(.subsonic, .album, id: album.id, title: album.displayName, subtitle: subtitle, artwork: SubsonicAPI.coverArtURL(for: album.coverArt, size: 300))
    }

    private func plexThumbnail(_ url: URL?) -> URL? {
        url?.plexResized(to: PlexImageSize.thumbnail)
    }

    private func songCount(_ count: Int?) -> String {
        guard let count, count > 0 else { return "" }
        return count == 1 ? "1 song" : "\(count) songs"
    }

    // MARK: - Songs

    /// The songs of a pick, in play order — fetched the way the iPhone
    /// fetches them, so a pick is the same songs whichever device made it.
    /// Nil when the server couldn't be asked, or doesn't have it any more.
    func songs(for pick: WatchPick) async -> [WatchSong]? {
        let plex = PlexAPI.shared
        let subsonic = SubsonicAPI.shared
        let ratingKey = ConvertedStream.plexRatingKey(contentID: pick.id) ?? ""
        let songs: [WatchSong]
        switch (pick.source, pick.kind) {
        case (.plex, .song):
            guard let metadata = await plex.lookupPlexSong(key: ratingKey)?.metadata else { return nil }
            songs = metadata.compactMap(plexSong)
        case (.plex, .album):
            guard let metadata = await plex.lookupAlbumTracks(key: ratingKey)?.metadata else { return nil }
            songs = metadata.compactMap(plexSong)
        case (.plex, .playlist):
            // Paged: Plex caps each response at 200.
            var fetched: [PlexMetadata] = []
            for _ in 0 ..< 50 {
                guard let page = await plex.lookupPlaylist(key: ratingKey, type: .song, ascending: true, offset: fetched.count)?.metadata else {
                    if fetched.isEmpty { return nil }
                    break
                }
                fetched += page
                if page.count < 200 { break }
            }
            songs = fetched.compactMap(plexSong)
        case (.subsonic, .song):
            guard let song = await subsonic.song(for: pick.id) else { return nil }
            songs = [song].compactMap(subsonicSong)
        case (.subsonic, .album):
            guard let album = await subsonic.album(for: pick.id) else { return nil }
            songs = (album.song ?? []).compactMap(subsonicSong)
        case (.subsonic, .playlist):
            guard let playlist = await subsonic.playlist(for: pick.id) else { return nil }
            songs = (playlist.entry ?? []).compactMap(subsonicSong)
        case (_, .artist):
            // Every album, oldest first, fetched together and flattened —
            // bounded as on the iPhone (30 albums, 200 songs).
            guard let albums = await albums(of: pick) else { return nil }
            let picks = albums.prefix(30).compactMap { $0.item.pick }
            let byAlbum = await withTaskGroup(of: (Int, [WatchSong]).self) { group in
                for (index, album) in picks.enumerated() {
                    group.addTask { (index, await self.songs(for: album) ?? []) }
                }
                var results = [[WatchSong]](repeating: [], count: picks.count)
                for await (index, songs) in group {
                    results[index] = songs
                }
                return results
            }
            songs = Array(byAlbum.joined().prefix(200))
        }
        var seen = Set<String>()
        return songs.filter { seen.insert($0.key).inserted }
    }

    /// An artist's albums, oldest first; nil when the server couldn't be asked.
    private func albums(of artist: WatchPick) async -> [(item: WatchBrowseItem, year: Int)]? {
        var albums: [(item: WatchBrowseItem, year: Int)] = []
        switch artist.source {
        case .plex:
            guard let key = ConvertedStream.plexRatingKey(contentID: artist.id),
                  let metadata = await PlexAPI.shared.lookupArtistAlbums(key: key)?.metadata else { return nil }
            for album in metadata {
                let year = album.year ?? album.parentYear
                guard let item = item(.plex, .album, id: album.sonosID, title: album.title, subtitle: year.map(String.init) ?? "", artwork: plexThumbnail(album.thumbImageURL)) else { continue }
                albums.append((item, year ?? 0))
            }
        case .subsonic:
            guard let found = await SubsonicAPI.shared.artist(for: artist.id) else { return nil }
            for album in found.album ?? [] {
                guard let item = subsonicAlbumItem(album) else { continue }
                albums.append((item, album.year ?? 0))
            }
        }
        // Stable, so albums of one year keep the server's order.
        return albums.enumerated()
            .sorted { ($0.element.year, $0.offset) < ($1.element.year, $1.offset) }
            .map { $0.element }
    }

    private func plexSong(_ metadata: PlexMetadata) -> WatchSong? {
        guard let id = metadata.sonosID, let sourceURL = metadata.streamURL else { return nil }
        return WatchSong(
            source: .plex,
            contentID: id,
            title: metadata.title,
            artist: metadata.grandparentTitle ?? metadata.originalTitle ?? "",
            album: metadata.parentTitle,
            artworkURL: plexThumbnail(metadata.thumbImageURL),
            duration: metadata.duration.map { Double($0) / 1000 },
            sourceURL: sourceURL,
            audioCodec: metadata.media?.first?.audioCodec
        )
    }

    private func subsonicSong(_ song: SubsonicSong) -> WatchSong? {
        guard let sourceURL = SubsonicAPI.streamURL(for: song.id, fileExtension: song.suffix) else { return nil }
        return WatchSong(
            source: .subsonic,
            contentID: song.id,
            title: song.title ?? "",
            artist: song.artist ?? "",
            album: song.album,
            artworkURL: SubsonicAPI.coverArtURL(for: song.coverArt, size: 300),
            duration: song.duration.map { Double($0) },
            sourceURL: sourceURL,
            audioCodec: song.suffix
        )
    }
}
