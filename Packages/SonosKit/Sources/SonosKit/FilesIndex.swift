import Foundation

/// Everything the Files provider serves — songs, albums, artists and
/// playlists, their lookups, and every sort order the lists offer — built
/// from the tracks in one pass off the main actor and swapped in whole.
/// Immutable once built, so the main actor's only work is the swap.
struct FilesIndex: Sendable {
    /// One array per sort and direction, as positions into `songs` or
    /// `albums`. Paging a sort is then a slice.
    struct Order<Sort: Hashable & Sendable>: Hashable, Sendable {
        var sort: Sort
        var descending: Bool
    }

    /// In title order.
    var songs: [PlayableContent] = []
    var albums: [PlayableContent] = []
    var artists: [PlayableContent] = []
    var playlists: [PlayableContent] = []
    var tracksByID: [String: FileTrack] = [:]
    var songsByID: [String: PlayableContent] = [:]
    var albumsByID: [String: PlayableContent] = [:]
    var artistsByID: [String: PlayableContent] = [:]
    var playlistsByID: [String: PlayableContent] = [:]
    var songIDsByAlbum: [String: [String]] = [:]
    var albumIDsByArtist: [String: [String]] = [:]
    var songIDsByPlaylist: [String: [String]] = [:]
    var songIDByPath: [String: String] = [:]
    var albumAdded: [String: Date] = [:]
    var albumYear: [String: Int] = [:]
    var songOrders: [Order<FilesLibraryService.SongSort>: [Int]] = [:]
    var albumOrders: [Order<FilesLibraryService.AlbumSort>: [Int]] = [:]

    static let empty = FilesIndex()

    func songOrder(_ sort: FilesLibraryService.SongSort, descending: Bool) -> [Int] {
        songOrders[Order(sort: sort, descending: descending)] ?? Array(songs.indices)
    }

    func albumOrder(_ sort: FilesLibraryService.AlbumSort, descending: Bool) -> [Int] {
        albumOrders[Order(sort: sort, descending: descending)] ?? Array(albums.indices)
    }

    /// The build, off whichever actor asks for it: the hashing and sorting
    /// of a big library never touch the main actor.
    @concurrent
    static func build(tracks: [FileTrack], playlists: [FilePlaylist], folderURL: URL?, artworkDirectory: URL) async -> FilesIndex {
        make(tracks: tracks, playlists: playlists, folderURL: folderURL, artworkDirectory: artworkDirectory)
    }

    private struct SongKeys {
        var title: String
        var artist: String
        var album: String
        var position: Int
        var added: Date
        var duration: Double
        var path: String
    }

    private struct AlbumKeys {
        var title: String
        var artist: String
        var year: Int
        var added: Date
    }

    /// The same build, synchronously — for callers that already are off
    /// the main actor, and tests.
    static func make(tracks unordered: [FileTrack], playlists filePlaylists: [FilePlaylist], folderURL: URL?, artworkDirectory: URL) -> FilesIndex {
        var index = FilesIndex()
        let tracks = unordered.sorted { NaturalSortKey.key(for: $0.relativePath) < NaturalSortKey.key(for: $1.relativePath) }

        // Pass one: what each album is called, dated and pictured.
        var albumArtwork: [String: URL] = [:]
        for track in tracks {
            let artistName = track.groupingArtist
            let albumID = FilesLibraryService.hash("album|\(artistName.lowercased())|\(track.albumTitle.lowercased())")
            if let added = track.modificationDate, (index.albumAdded[albumID] ?? .distantPast) < added {
                index.albumAdded[albumID] = added
            }
            if let year = track.year, (index.albumYear[albumID] ?? 0) < year {
                index.albumYear[albumID] = year
            }
            if albumArtwork[albumID] == nil, let name = track.artworkFileName {
                albumArtwork[albumID] = artworkDirectory.appendingPathComponent(name)
            }
        }

        var songs: [PlayableContent] = []
        var songKeys: [SongKeys] = []
        songs.reserveCapacity(tracks.count)
        songKeys.reserveCapacity(tracks.count)

        for track in tracks {
            let artistName = track.groupingArtist
            let artistID = FilesLibraryService.hash("artist|\(artistName.lowercased())")
            let albumID = FilesLibraryService.hash("album|\(artistName.lowercased())|\(track.albumTitle.lowercased())")
            let songID = FilesLibraryService.hash("song|\(track.relativePath)")
            let url = folderURL?.appendingPathComponent(track.relativePath)
            let artwork = track.artworkFileName.map { artworkDirectory.appendingPathComponent($0) } ?? albumArtwork[albumID]
            let year = index.albumYear[albumID]
            let songArtist = track.artist ?? artistName
            // Checked here as well as when read: an index stored before the
            // check existed can carry a value `Duration` would trap on.
            let duration = FilesLibraryService.playableDuration(track.duration)

            let song = PlayableContent(
                title: track.title,
                subtitle: [songArtist, track.fileExtension.uppercased()]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • "),
                thumbnail: artwork,
                artwork: artwork,
                content: .init(service: .files, id: songID, type: .track, location: url),
                // The file itself, even while it's still in iCloud: the
                // on-device player reads it, a row's preview plays it in
                // full, and opening it makes iCloud fetch it.
                previewURL: url,
                metadata: .init(
                    duration: duration.map { Duration.seconds($0) },
                    artist: songArtist,
                    artistID: artistID,
                    album: track.albumTitle,
                    albumID: albumID,
                    albumYear: year.flatMap { date(year: $0) },
                    position: track.trackNumber,
                    audioCodec: track.fileExtension,
                    isPlayable: track.isDownloaded
                )
            )
            songs.append(song)
            songKeys.append(SongKeys(
                title: NaturalSortKey.key(for: track.title),
                artist: NaturalSortKey.key(for: songArtist),
                album: NaturalSortKey.key(for: track.albumTitle),
                position: track.trackNumber ?? 0,
                added: track.modificationDate ?? .distantPast,
                duration: duration ?? 0,
                path: track.relativePath
            ))
            index.tracksByID[songID] = track
            index.songIDByPath[track.relativePath] = songID
            index.songIDsByAlbum[albumID, default: []].append(songID)

            if index.albumsByID[albumID] == nil {
                index.albumsByID[albumID] = PlayableContent(
                    title: track.albumTitle,
                    subtitle: [artistName, year.map(String.init) ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " • "),
                    thumbnail: artwork,
                    artwork: artwork,
                    content: .init(service: .files, id: albumID, type: .album, location: nil),
                    metadata: .init(
                        artist: artistName,
                        artistID: artistID,
                        album: track.albumTitle,
                        albumID: albumID,
                        albumYear: year.flatMap { date(year: $0) }
                    )
                )
                index.albumIDsByArtist[artistID, default: []].append(albumID)
            }

            if index.artistsByID[artistID] == nil {
                index.artistsByID[artistID] = PlayableContent(
                    title: artistName,
                    subtitle: "",
                    thumbnail: artwork,
                    artwork: artwork,
                    content: .init(service: .files, id: artistID, type: .artist, location: nil),
                    metadata: .init(artist: artistName, artistID: artistID)
                )
            }
        }

        // Songs live in title order; every other order is positions into that.
        let titleOrder = Array(songs.indices).sorted { songKeys[$0].title < songKeys[$1].title || (songKeys[$0].title == songKeys[$1].title && songKeys[$0].path < songKeys[$1].path) }
        songs = titleOrder.map { songs[$0] }
        songKeys = titleOrder.map { songKeys[$0] }
        index.songs = songs
        index.songsByID = Dictionary(songs.map { ($0.content.id, $0) }, uniquingKeysWith: { first, _ in first })

        for sort in FilesLibraryService.SongSort.allCases {
            let ascending: (SongKeys, SongKeys) -> Bool
            switch sort {
            case .title:
                ascending = { l, r in l.title != r.title ? l.title < r.title : l.path < r.path }
            case .artist:
                ascending = { l, r in l.artist != r.artist ? l.artist < r.artist : l.title < r.title }
            case .album:
                ascending = { l, r in l.album != r.album ? l.album < r.album : l.position < r.position }
            case .recentlyAdded:
                ascending = { l, r in l.added < r.added }
            case .duration:
                ascending = { l, r in l.duration < r.duration }
            }
            let positions = Array(songs.indices)
            index.songOrders[Order(sort: sort, descending: false)] = positions.sorted { ascending(songKeys[$0], songKeys[$1]) }
            index.songOrders[Order(sort: sort, descending: true)] = positions.sorted { ascending(songKeys[$1], songKeys[$0]) }
        }

        // Albums and artists in title order, with keys for the other orders.
        var albums = Array(index.albumsByID.values)
        var albumKeys = albums.map { album in
            AlbumKeys(
                title: NaturalSortKey.key(for: album.title),
                artist: NaturalSortKey.key(for: album.metadata?.artist ?? ""),
                year: index.albumYear[album.content.id] ?? 0,
                added: index.albumAdded[album.content.id] ?? .distantPast
            )
        }
        let albumTitleOrder = Array(albums.indices).sorted { albumKeys[$0].title != albumKeys[$1].title ? albumKeys[$0].title < albumKeys[$1].title : albumKeys[$0].artist < albumKeys[$1].artist }
        albums = albumTitleOrder.map { albums[$0] }
        albumKeys = albumTitleOrder.map { albumKeys[$0] }
        index.albums = albums

        for sort in FilesLibraryService.AlbumSort.allCases {
            let ascending: (AlbumKeys, AlbumKeys) -> Bool
            switch sort {
            case .title:
                ascending = { l, r in l.title != r.title ? l.title < r.title : l.artist < r.artist }
            case .artist:
                ascending = { l, r in l.artist != r.artist ? l.artist < r.artist : l.title < r.title }
            case .year:
                ascending = { l, r in l.year != r.year ? l.year < r.year : l.title < r.title }
            case .recentlyAdded:
                ascending = { l, r in l.added < r.added }
            }
            let positions = Array(albums.indices)
            index.albumOrders[Order(sort: sort, descending: false)] = positions.sorted { ascending(albumKeys[$0], albumKeys[$1]) }
            index.albumOrders[Order(sort: sort, descending: true)] = positions.sorted { ascending(albumKeys[$1], albumKeys[$0]) }
        }

        index.artists = index.artistsByID.values
            .map { ($0, NaturalSortKey.key(for: $0.title)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        var playlists: [PlayableContent] = []
        for playlist in filePlaylists {
            let id = FilesLibraryService.hash("playlist|\(playlist.relativePath)")
            let ids = playlist.trackRelativePaths.compactMap { index.songIDByPath[$0] }
            let first = ids.first.flatMap { index.songsByID[$0] }
            let content = PlayableContent(
                title: playlist.title,
                subtitle: ids.isEmpty ? "Empty" : (ids.count == 1 ? "1 song" : "\(ids.count) songs"),
                thumbnail: first?.thumbnail,
                artwork: first?.artwork,
                content: .init(service: .files, id: id, type: .playlist, location: folderURL?.appendingPathComponent(playlist.relativePath))
            )
            index.playlistsByID[id] = content
            index.songIDsByPlaylist[id] = ids
            playlists.append(content)
        }
        index.playlists = playlists
            .map { ($0, NaturalSortKey.key(for: $0.title)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        return index
    }

    private static func date(year: Int) -> Date? {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 1, day: 1))
    }
}
