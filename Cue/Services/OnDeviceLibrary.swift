import Foundation
import SonosKit

/// The two grouped pages of the on-device library. A destination's
/// associated value, so it lives at the top level with the router's access.
public enum OnDeviceCollection: Hashable, Sendable {
    case albums
    case artists

    public var title: String {
        switch self {
        case .albums: "Albums"
        case .artists: "Artists"
        }
    }

    public var systemImage: String {
        switch self {
        case .albums: "smallcircle.circle.fill"
        case .artists: "music.mic"
        }
    }
}

/// What plays with no connection at all: the download manager's finished
/// Plex and Subsonic songs, the Apple Music songs the Music app has
/// downloaded, and the songs of the Files folder that are on this device
/// rather than only in iCloud. While `OfflineMode` is active the Home tab
/// browses just these — as Artists, Albums and Songs, the way a provider's
/// library reads, grouped and searched here rather than on a server none
/// of them can reach. Each provider's own Downloaded page reads the same
/// library narrowed to that `service`.
///
/// Album and artist containers minted here carry an `ondevice|` id that
/// `LocalPlaybackService` and `QueueManager` recognise and expand back into
/// the songs, so Play All on one of these pages never asks a server.
@MainActor
enum OnDeviceLibrary {
    // MARK: - Songs

    /// Every finished download as a playable song, by title. The local
    /// player finds the file through the download manager, so these play
    /// with the server unreachable.
    static var downloadedSongs: [PlayableContent] {
        DownloadManager.shared.completed
            .map(\.playableContent)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The Apple Music songs downloaded in the Music app, as library
    /// tracks. `ApplicationMusicPlayer` plays those from the local copy.
    static var appleSongs: [PlayableContent] {
        AppleDownloadsIndex.shared.songs
    }

    /// The Files folder's songs that are here: `isPlayable` follows the
    /// index's download flag, which a scan and an iCloud eviction both keep
    /// current. Everything for a folder on the device itself.
    static var fileSongs: [PlayableContent] {
        FilesLibraryService.shared.songs.filter(\.isPlayable)
    }

    /// Downloads, then Apple's, then the folder — what Play and Shuffle
    /// on Home take.
    static var allSongs: [PlayableContent] {
        downloadedSongs + appleSongs + fileSongs
    }

    /// Everything here from one provider, or all of it for nil.
    static func allSongs(in service: MusicService?) -> [PlayableContent] {
        songs(in: service).map(\.track)
    }

    static var isEmpty: Bool {
        isEmpty(in: nil)
    }

    static func isEmpty(in service: MusicService?) -> Bool {
        switch service {
        case .apple: appleSongs.isEmpty
        case .files: fileSongs.isEmpty
        case .plex, .subsonic: !DownloadManager.shared.completed.contains { $0.service == service }
        case nil: DownloadManager.shared.completed.isEmpty && appleSongs.isEmpty && fileSongs.isEmpty
        default: true
        }
    }

    /// Bumped whenever the songs here can have changed — a download
    /// finishing or being removed, the Apple index or the Files index
    /// rebuilding — for the lists that took a snapshot to know to take
    /// another.
    static var changeToken: Int {
        (DownloadManager.shared.completed.count &* 31 &+ FilesLibraryService.shared.indexVersion) &* 31
            &+ AppleDownloadsIndex.shared.version
    }

    // MARK: - Sorts

    enum SongSort: CaseIterable {
        case title, artist, album, added

        var label: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .added: "Recently Downloaded"
            }
        }

        var ascendingLabel: String {
            switch self {
            case .title, .artist, .album: "A – Z"
            case .added: "Oldest First"
            }
        }

        var descendingLabel: String {
            switch self {
            case .title, .artist, .album: "Z – A"
            case .added: "Newest First"
            }
        }

        var prefersDescending: Bool { self == .added }
    }

    enum GroupSort: CaseIterable {
        case title, added

        var label: String {
            switch self {
            case .title: "Title"
            case .added: "Recently Downloaded"
            }
        }
    }

    /// A song with when it arrived on the device. Downloads know, and
    /// Apple's carry the day they joined the library; the Files folder's
    /// songs don't, so they sort behind every download.
    private struct Song {
        let track: PlayableContent
        let added: Date
    }

    private static var songs: [Song] {
        let apple = AppleDownloadsIndex.shared
        return DownloadManager.shared.completed.map { Song(track: $0.playableContent, added: $0.createdAt) }
            + appleSongs.map { Song(track: $0, added: apple.addedDate(for: $0) ?? .distantPast) }
            + fileSongs.map { Song(track: $0, added: .distantPast) }
    }

    /// The songs of one provider, or every song for nil.
    private static func songs(in service: MusicService?) -> [Song] {
        guard let service else { return songs }
        return songs.filter { $0.track.content.service == service }
    }

    static func songs(sortedBy sort: SongSort, descending: Bool, in service: MusicService? = nil) -> [PlayableContent] {
        let songs = Self.songs(in: service)
        let ordered: [Song]
        switch sort {
        case .title:
            ordered = songs.sorted { compare($0.track.title, $1.track.title) }
        case .artist:
            ordered = songs.sorted {
                let a = $0.track.metadata?.artist ?? "", b = $1.track.metadata?.artist ?? ""
                if a.caseInsensitiveCompare(b) != .orderedSame { return compare(a, b) }
                return albumOrder($0.track, $1.track)
            }
        case .album:
            ordered = songs.sorted {
                let a = $0.track.metadata?.album ?? "", b = $1.track.metadata?.album ?? ""
                if a.caseInsensitiveCompare(b) != .orderedSame { return compare(a, b) }
                return positionOrder($0.track, $1.track)
            }
        case .added:
            ordered = songs.sorted { $0.added < $1.added }
        }
        return (descending ? ordered.reversed() : ordered).map(\.track)
    }

    /// Songs whose title, artist or album contains the query. Local, so it
    /// answers with no network at all.
    static func searchSongs(_ query: String, in service: MusicService? = nil) -> [PlayableContent] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let songs = Self.songs(sortedBy: .title, descending: false, in: service)
        guard !query.isEmpty else { return songs }
        return songs.filter { track in
            [track.title, track.metadata?.artist, track.metadata?.album, track.subtitle]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: - Albums & artists

    /// An album or artist on the device: what its rows share, the songs
    /// here, and a container the players expand back into them.
    struct Group: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let artwork: URL?
        let tracks: [PlayableContent]
        /// When the newest of its songs arrived, for the recency sort.
        let latestAdded: Date
        let container: PlayableContent

        var trackCount: Int { tracks.count }
    }

    static var albums: [Group] { groups(.albums, sortedBy: .title, descending: false) }
    static var artists: [Group] { groups(.artists, sortedBy: .title, descending: false) }

    static func groups(_ collection: OnDeviceCollection, sortedBy sort: GroupSort, descending: Bool, in service: MusicService? = nil) -> [Group] {
        var buckets: [String: [Song]] = [:]
        var order: [String] = []
        for song in songs(in: service) {
            let key = groupKey(collection, for: song.track)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(song)
        }

        let groups = order.compactMap { key -> Group? in
            guard let bucket = buckets[key], let first = bucket.first else { return nil }
            let tracks = bucket.map(\.track).sorted(by: collection == .albums ? positionOrder : albumOrder)
            let latest = bucket.map(\.added).max() ?? first.added
            let service = first.track.content.service
            let artwork = tracks.compactMap { $0.thumbnail ?? $0.artwork }.first

            switch collection {
            case .albums:
                let title = name(first.track.metadata?.album, fallback: "Unknown Album")
                let artist = name(first.track.metadata?.artist, fallback: service.title)
                return Group(
                    id: key,
                    title: title,
                    subtitle: artist,
                    artwork: artwork,
                    tracks: tracks,
                    latestAdded: latest,
                    container: PlayableContent(
                        title: title,
                        subtitle: artist,
                        thumbnail: artwork,
                        artwork: artwork,
                        content: .init(service: service, id: containerID(.albums, key: key), type: .album, location: nil),
                        metadata: .init(artist: artist, album: title)
                    )
                )
            case .artists:
                let title = name(first.track.metadata?.artist, fallback: "Unknown Artist")
                let albumCount = Set(tracks.map { groupKey(.albums, for: $0) }).count
                let subtitle = [
                    albumCount == 1 ? "1 album" : "\(albumCount) albums",
                    tracks.count == 1 ? "1 song" : "\(tracks.count) songs",
                ].joined(separator: " • ")
                return Group(
                    id: key,
                    title: title,
                    subtitle: subtitle,
                    artwork: artwork,
                    tracks: tracks,
                    latestAdded: latest,
                    container: PlayableContent(
                        title: title,
                        subtitle: subtitle,
                        thumbnail: artwork,
                        artwork: artwork,
                        content: .init(service: service, id: containerID(.artists, key: key), type: .artist, location: nil),
                        metadata: .init(artist: title)
                    )
                )
            }
        }

        let ordered: [Group]
        switch sort {
        case .title:
            ordered = groups.sorted { compare($0.title, $1.title) }
        case .added:
            ordered = groups.sorted { $0.latestAdded < $1.latestAdded }
        }
        return descending ? ordered.reversed() : ordered
    }

    /// Groups whose name, line under it, or a song's title contains the
    /// query.
    static func groups(_ collection: OnDeviceCollection, matching query: String, sortedBy sort: GroupSort, descending: Bool, in service: MusicService? = nil) -> [Group] {
        let groups = Self.groups(collection, sortedBy: sort, descending: descending, in: service)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.filter { group in
            group.title.localizedCaseInsensitiveContains(query)
                || group.subtitle.localizedCaseInsensitiveContains(query)
                || group.tracks.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Everything on the device that matches a query, for the Search tab
    /// while offline: artists and albums by name, songs by title, artist or
    /// album. An empty query matches nothing.
    static func search(_ query: String) -> (artists: [Group], albums: [Group], songs: [PlayableContent]) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ([], [], []) }
        let artists = groups(.artists, sortedBy: .title, descending: false).filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
        let albums = groups(.albums, sortedBy: .title, descending: false).filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
        return (artists, albums, searchSongs(query))
    }

    /// The songs of one album or artist that are here, as a list with a
    /// Play All. Read live, so a download removed inside the list leaves
    /// the screen too.
    static func destination(for group: Group) -> RouterDestination {
        let container = group.container
        return .playableList(
            title: group.title,
            playAllItem: container,
            showSectionIndex: false,
            loadingStatus: {
                let count = tracks(inContainer: container)?.count ?? 0
                return count == 0 ? nil : (count == 1 ? "1 song" : "\(count) songs")
            },
            changeToken: { changeToken },
            action: { offset in
                offset == 0 ? (tracks(inContainer: container) ?? []) : []
            }
        )
    }

    // MARK: - Containers

    /// The id prefix of the containers minted here. Anything the players
    /// see with it is expanded from what's on the device, never a server.
    nonisolated static let containerIDPrefix = "ondevice|"

    /// Stands for every song on the device, behind the Songs page's Play All.
    static var allSongsContainer: PlayableContent {
        allSongsContainer(in: nil)
    }

    /// Every song on the device from one provider — or all of them for
    /// nil — as one container, behind a Downloaded page's Play All.
    static func allSongsContainer(in service: MusicService?) -> PlayableContent {
        let first = songs(in: service).first?.track
        let artwork = first.flatMap { $0.thumbnail ?? $0.artwork }
        let id = service.map { "\(containerIDPrefix)all|\($0.sonosRawValue)" } ?? "\(containerIDPrefix)all"
        return PlayableContent(
            title: service.map { "Downloaded • \($0.title)" } ?? "On This Device",
            subtitle: service == nil ? "Downloads and files" : "On this device",
            thumbnail: artwork,
            artwork: artwork,
            content: .init(service: service ?? first?.content.service ?? .plex, id: id, type: .playlist, location: nil)
        )
    }

    /// Whether this is one of the containers minted here.
    nonisolated static func isContainer(_ content: PlayableContent) -> Bool {
        content.content.id.hasPrefix(containerIDPrefix)
    }

    /// The songs a container minted here stands for, in play order — or nil
    /// for anything else, so callers fall through to their usual expansion.
    static func tracks(inContainer container: PlayableContent) -> [PlayableContent]? {
        guard isContainer(container) else { return nil }
        let rest = container.content.id.dropFirst(containerIDPrefix.count)
        if rest == "all" {
            return songs.map(\.track).sorted(by: albumOrder)
        }
        if rest.hasPrefix("all|") {
            let service = MusicService(service: String(rest.dropFirst("all|".count)))
            return songs(in: service).map(\.track).sorted(by: albumOrder)
        }
        let parts = rest.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        let collection: OnDeviceCollection = parts[0] == "album" ? .albums : .artists
        let key = parts[1]
        let tracks = songs.map(\.track).filter { groupKey(collection, for: $0) == key }
        return tracks.sorted(by: collection == .albums ? positionOrder : albumOrder)
    }

    private static func containerID(_ collection: OnDeviceCollection, key: String) -> String {
        "\(containerIDPrefix)\(collection == .albums ? "album" : "artist")|\(key)"
    }

    // MARK: - Copy

    /// What to do to have something here, for the empty pages: one
    /// provider's way of downloading, or every way for nil.
    static func emptyDescription(for service: MusicService?) -> String {
        switch service {
        case .apple:
            "Download songs, albums or playlists in the Music app and they'll be here to play on this device, with or without a network."
        case .plex:
            "Download a Plex song, album or playlist from its menu — or an album's download button — to keep it on this device."
        case .subsonic:
            "Download a Subsonic song, album or playlist from its menu — or an album's download button — to keep it on this device."
        case .files:
            "Download songs from your iCloud Drive folder from their menus, or keep the folder on this device, and they'll be here."
        default:
            "Download Plex or Subsonic songs from their menus, download Apple Music songs in the Music app, or keep a Files folder on this device, and they'll be here when you're offline."
        }
    }

    // MARK: - Keys & ordering

    /// What a song is grouped under: the service plus the album or artist
    /// id when the service gave one, else the names — so two editions of
    /// an album stay apart on Plex, and untagged songs still land together.
    private static func groupKey(_ collection: OnDeviceCollection, for track: PlayableContent) -> String {
        let service = track.content.service.sonosRawValue
        let metadata = track.metadata
        switch collection {
        case .albums:
            if let id = metadata?.albumID, !id.isEmpty { return "\(service)|id|\(id)" }
            return "\(service)|name|\((metadata?.album ?? "").lowercased())|\((metadata?.artist ?? "").lowercased())"
        case .artists:
            if let id = metadata?.artistID, !id.isEmpty { return "\(service)|id|\(id)" }
            return "\(service)|name|\((metadata?.artist ?? "").lowercased())"
        }
    }

    private static func name(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func compare(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    /// Song order within an album: position, then title.
    private static func positionOrder(_ a: PlayableContent, _ b: PlayableContent) -> Bool {
        let pa = a.metadata?.position ?? Int.max, pb = b.metadata?.position ?? Int.max
        if pa != pb { return pa < pb }
        return compare(a.title, b.title)
    }

    /// Song order across albums: album, then position.
    private static func albumOrder(_ a: PlayableContent, _ b: PlayableContent) -> Bool {
        let aa = a.metadata?.album ?? "", ab = b.metadata?.album ?? ""
        if aa.caseInsensitiveCompare(ab) != .orderedSame { return compare(aa, ab) }
        return positionOrder(a, b)
    }
}

extension DownloadManager.Item {
    /// The download as the song it was queued from — enough for a row, a
    /// menu, and the local player, which resolves the file by the same key
    /// the download was stored under. The track kept on the manifest when
    /// there is one, with its album and artist; downloads from before that
    /// was kept are rebuilt from their row.
    var playableContent: PlayableContent {
        if let track { return track }
        return PlayableContent(
            title: title,
            subtitle: subtitle,
            thumbnail: artwork,
            artwork: artwork,
            content: .init(service: service, id: contentID, type: .track, location: nil),
            previewURL: url,
            metadata: .init(artist: subtitle, audioCodec: fileExtension)
        )
    }
}
