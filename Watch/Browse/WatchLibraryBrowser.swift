import Foundation
import MusicSearchKit
import WatchSync

/// Browses the Plex and Subsonic servers from the watch, with MusicSearchKit
/// and the sign-ins the iPhone shared (`WatchAccounts`): pages of playlists,
/// albums and artists, and the songs of one to put on the watch. No iPhone
/// needed — the requests go from the watch to the server, over Wi‑Fi or
/// cellular, or through the iPhone when it's connected over Bluetooth.
///
/// Rows carry the same ids the iPhone's library gives the same things (a
/// Plex item's Sonos-style id, a Subsonic id), so the keys match
/// (`WatchKeys`): an album added here shows as added on the iPhone, and a
/// song in it is one file whichever device added it.
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
            let sections: [WatchBrowseSection] = switch source {
            case .plex: [.playlists, .albums, .artists]
            case .subsonic: [.playlists, .recentlyAdded, .albums, .artists]
            }
            return WatchBrowsePage(
                title: source.title,
                items: sections.map { WatchBrowseItem(id: $0.rawValue, title: $0.title, symbol: $0.symbol, destination: .section(source, $0)) }
            )

        case .section, .artist:
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
                message: listing.items.isEmpty ? "Nothing here, or the server can't be reached." : nil
            )
        }
    }

    /// One page of a list from the server. Lists that come whole answer at
    /// offset 0 only.
    private func fetch(_ path: WatchBrowsePath, offset: Int) async -> [WatchBrowseItem] {
        let plex = PlexAPI.shared
        let subsonic = SubsonicAPI.shared
        switch path {
        case .section(.plex, .playlists):
            guard offset == 0 else { return [] }
            return await plex.playlists().compactMap { playlist in
                item(.plex, .playlist, id: playlist.sonosID, title: playlist.title, subtitle: songCount(playlist.leafCount), artwork: plexThumbnail(playlist.thumbImageURL))
            }
        case .section(.plex, .albums):
            return await plex.albums(offset: offset).compactMap { album in
                item(.plex, .album, id: album.sonosID, title: album.title ?? "", subtitle: [album.parentTitle, album.year.map(String.init)].compactMap { $0 }.joined(separator: " • "), artwork: plexThumbnail(album.thumbImageURL))
            }
        case .section(.plex, .artists):
            return await plex.artists(offset: offset).compactMap { artist in
                item(.plex, .artist, id: artist.sonosID, title: artist.title, subtitle: "", artwork: plexThumbnail(artist.thumbImageURL))
            }
        case .section(.plex, .recentlyAdded):
            return []
        case .section(.subsonic, .playlists):
            guard offset == 0 else { return [] }
            return await subsonic.playlists().compactMap { playlist in
                item(.subsonic, .playlist, id: playlist.id, title: playlist.name ?? "", subtitle: [playlist.owner, songCount(playlist.songCount)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "), artwork: SubsonicAPI.coverArtURL(for: playlist.coverArt, size: 300))
            }
        case .section(.subsonic, .albums):
            return await subsonic.albumList(type: SubsonicAlbumSort.title.apiType, size: 50, offset: offset).compactMap(subsonicAlbumItem)
        case .section(.subsonic, .recentlyAdded):
            return await subsonic.albumList(type: SubsonicAlbumSort.recentlyAdded.apiType, size: 50, offset: offset).compactMap(subsonicAlbumItem)
        case .section(.subsonic, .artists):
            guard offset == 0 else { return [] }
            return await subsonic.artists().compactMap { artist in
                item(.subsonic, .artist, id: artist.id, title: artist.name ?? "", subtitle: "", artwork: SubsonicAPI.coverArtURL(for: artist.coverArt, size: 300))
            }
        case let .artist(ref):
            guard offset == 0 else { return [] }
            switch ref.source {
            case .plex:
                guard let key = ConvertedStream.plexRatingKey(contentID: ref.id) else { return [] }
                let albums = await plex.lookupArtistAlbums(key: key)?.metadata ?? []
                return albums.compactMap { album in
                    item(.plex, .album, id: album.sonosID, title: album.title, subtitle: (album.year ?? album.parentYear).map(String.init) ?? "", artwork: plexThumbnail(album.thumbImageURL))
                }
            case .subsonic:
                return (await subsonic.artist(for: ref.id)?.album ?? []).compactMap(subsonicAlbumItem)
            }
        case .root, .source:
            return []
        }
    }

    private func title(of path: WatchBrowsePath) -> String {
        switch path {
        case .root: "Add Music"
        case let .source(source): source.title
        case let .section(_, section): section.title
        case let .artist(ref): ref.title
        }
    }

    /// An artist's page offers the artist whole, where that can go on the
    /// watch (Subsonic, as on the iPhone).
    private func container(of path: WatchBrowsePath) -> WatchBrowseItem? {
        guard case let .artist(ref) = path, ref.source == .subsonic else { return nil }
        return item(ref.source, .artist, id: ref.id, title: ref.title, subtitle: ref.subtitle, artwork: ref.artworkURL, opens: false)
    }

    // MARK: - Rows

    /// A row for an album, playlist or artist: an artist opens on its
    /// albums; what can go on the watch whole carries its reference and the
    /// key it'll have there. Plex artists don't go whole, as on the iPhone.
    private func item(_ source: WatchSource, _ kind: WatchCollection.Kind, id: String?, title: String, subtitle: String, artwork: URL?, opens: Bool = true) -> WatchBrowseItem? {
        guard let id, !id.isEmpty else { return nil }
        let ref = WatchContentRef(source: source, kind: kind, id: id, title: title, subtitle: subtitle, artworkURL: artwork)
        let canAdd = !(source == .plex && kind == .artist)
        return WatchBrowseItem(
            id: "\(kind.rawValue)-\(id)",
            title: title,
            subtitle: subtitle,
            artworkURL: artwork,
            destination: kind == .artist && opens ? .artist(ref) : nil,
            content: canAdd ? ref : nil,
            collectionKey: canAdd ? WatchKeys.collection(kind: kind, source: source, id: id) : nil
        )
    }

    private func subsonicAlbumItem(_ album: SubsonicAlbum) -> WatchBrowseItem? {
        item(.subsonic, .album, id: album.id, title: album.displayName, subtitle: [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " • "), artwork: SubsonicAPI.coverArtURL(for: album.coverArt, size: 300))
    }

    private func plexThumbnail(_ url: URL?) -> URL? {
        url?.plexResized(to: PlexImageSize.thumbnail)
    }

    private func songCount(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count == 1 ? "1 song" : "\(count) songs"
    }

    // MARK: - Songs

    /// The songs of an album, playlist or artist, in play order, as the
    /// watch fetches them at `quality` — fetched the way the iPhone fetches
    /// them, so a collection is the same songs whichever device added it.
    func tracks(for ref: WatchContentRef, quality: WatchDownloadQuality) async -> [WatchTrack] {
        let plex = PlexAPI.shared
        let subsonic = SubsonicAPI.shared
        var tracks: [WatchTrack] = []
        switch (ref.source, ref.kind) {
        case (.plex, .album):
            guard let key = ConvertedStream.plexRatingKey(contentID: ref.id) else { return [] }
            tracks = (await plex.lookupAlbumTracks(key: key)?.metadata ?? []).compactMap(plexTrack)
        case (.plex, .playlist):
            guard let key = ConvertedStream.plexRatingKey(contentID: ref.id) else { return [] }
            // Paged: Plex caps each response at 200.
            for _ in 0 ..< 50 {
                guard let page = await plex.lookupPlaylist(key: key, type: .song, ascending: true, offset: tracks.count)?.metadata,
                      !page.isEmpty else { break }
                tracks += page.compactMap(plexTrack)
                if page.count < 200 { break }
            }
        case (.subsonic, .album):
            tracks = (await subsonic.album(for: ref.id)?.song ?? []).compactMap(subsonicTrack)
        case (.subsonic, .playlist):
            tracks = (await subsonic.playlist(for: ref.id)?.entry ?? []).compactMap(subsonicTrack)
        case (.subsonic, .artist):
            // Every album, oldest first, fetched together and flattened —
            // bounded as on the iPhone (30 albums, 200 songs).
            let albums = (await subsonic.artist(for: ref.id)?.album ?? [])
                .sorted { ($0.year ?? 0) < ($1.year ?? 0) }
                .prefix(30)
            let byAlbum = await withTaskGroup(of: (Int, [SubsonicSong]).self) { group in
                for (index, album) in albums.enumerated() {
                    group.addTask { (index, await subsonic.album(for: album.id)?.song ?? []) }
                }
                var results = [[SubsonicSong]](repeating: [], count: albums.count)
                for await (index, songs) in group {
                    results[index] = songs
                }
                return results
            }
            tracks = Array(byAlbum.flatMap { $0 }.prefix(200)).compactMap(subsonicTrack)
        case (.plex, .artist), (_, .songs):
            return []
        }
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.key).inserted }.map { $0.converted(to: quality) }
    }

    /// The collection a reference stands for on the watch, holding these songs.
    func collection(for ref: WatchContentRef, tracks: [WatchTrack], addedAt: Date) -> WatchCollection {
        WatchCollection(
            key: WatchKeys.collection(kind: ref.kind, source: ref.source, id: ref.id),
            kind: ref.kind,
            title: ref.title,
            subtitle: ref.subtitle,
            artworkURL: ref.artworkURL,
            addedAt: addedAt,
            trackKeys: tracks.map(\.key)
        )
    }

    private func plexTrack(_ metadata: PlexMetadata) -> WatchTrack? {
        guard let id = metadata.sonosID, let sourceURL = metadata.streamURL else { return nil }
        let codec = metadata.media?.first?.audioCodec
        return WatchTrack(
            key: WatchKeys.track(source: .plex, id: id),
            title: metadata.title,
            artist: metadata.grandparentTitle ?? metadata.originalTitle ?? "",
            album: metadata.parentTitle,
            artworkURL: plexThumbnail(metadata.thumbImageURL),
            streamURL: sourceURL,
            fileExtension: codec ?? "mp3",
            duration: metadata.duration.map { Double($0) / 1000 },
            origin: WatchTrackOrigin(source: .plex, contentID: id, sourceURL: sourceURL, audioCodec: codec)
        )
    }

    private func subsonicTrack(_ song: SubsonicSong) -> WatchTrack? {
        guard let sourceURL = SubsonicAPI.streamURL(for: song.id, fileExtension: song.suffix) else { return nil }
        return WatchTrack(
            key: WatchKeys.track(source: .subsonic, id: song.id),
            title: song.title ?? "",
            artist: song.artist ?? "",
            album: song.album,
            artworkURL: SubsonicAPI.coverArtURL(for: song.coverArt, size: 300),
            streamURL: sourceURL,
            fileExtension: song.suffix ?? "mp3",
            duration: song.duration.map { Double($0) },
            origin: WatchTrackOrigin(source: .subsonic, contentID: song.id, sourceURL: sourceURL, audioCodec: song.suffix)
        )
    }
}

extension WatchTrack {
    /// This song's stream at `quality`, built from its origin the way the
    /// iPhone builds it (`ConvertedStream`). One with no origin stays as it is.
    func converted(to quality: WatchDownloadQuality) -> WatchTrack {
        guard let origin, let service = ConvertedStream.Service(rawValue: origin.source.rawValue) else { return self }
        let stream = ConvertedStream.stream(
            service: service,
            contentID: origin.contentID,
            sourceURL: origin.sourceURL,
            audioCodec: origin.audioCodec,
            format: quality.bitrate == nil ? .original : .mp3,
            bitrate: quality.bitrate ?? StreamTranscoding.defaultBitrate
        )
        return withStream(stream.url, fileExtension: stream.fileExtension, quality: quality)
    }
}
