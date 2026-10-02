import Foundation

/// Where a song comes from on its server — enough for either device to
/// build its stream again at another quality.
public struct WatchTrackOrigin: Codable, Hashable, Sendable {
    public let source: WatchSource
    public let contentID: String
    /// The original file.
    public let sourceURL: URL
    /// The file's own format (`flac`, `mp3`…), as the server reports it.
    public let audioCodec: String?

    public init(source: WatchSource, contentID: String, sourceURL: URL, audioCodec: String?) {
        self.source = source
        self.contentID = contentID
        self.sourceURL = sourceURL
        self.audioCodec = audioCodec
    }
}

/// A song the watch keeps: what it shows, and the URL it downloads the file
/// from — a Plex or Subsonic stream at the library's quality,
/// self-authenticating. `key` is the same on both devices (`WatchKeys`,
/// matching the iPhone's download manager): stable per track and safe as a
/// file name, so a song in two albums is one file.
public struct WatchTrack: Codable, Hashable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let streamURL: URL
    public let fileExtension: String
    public let duration: TimeInterval?
    /// Nil for songs put on the watch before origins were kept; those keep
    /// their stream until they're added again.
    public let origin: WatchTrackOrigin?
    /// The quality `streamURL` delivers; nil for songs from before.
    public let quality: WatchDownloadQuality?

    public var id: String { key }

    public init(
        key: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        streamURL: URL,
        fileExtension: String,
        duration: TimeInterval? = nil,
        origin: WatchTrackOrigin? = nil,
        quality: WatchDownloadQuality? = nil
    ) {
        self.key = key
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.streamURL = streamURL
        self.fileExtension = fileExtension
        self.duration = duration
        self.origin = origin
        self.quality = quality
    }

    /// The same song fetched from another stream, at `quality`.
    public func withStream(_ url: URL, fileExtension: String, quality: WatchDownloadQuality?) -> WatchTrack {
        WatchTrack(
            key: key,
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            streamURL: url,
            fileExtension: fileExtension,
            duration: duration,
            origin: origin,
            quality: quality
        )
    }

    /// Whether this is the same download as `other`: the same song from the
    /// same server at the same quality, whatever the stream's sign-in
    /// parameters say. Each device signs a Subsonic stream with its own
    /// salt, so one song's URL differs between them, and a file that's here
    /// shouldn't come down again for that.
    public func isSameDownload(as other: WatchTrack) -> Bool {
        guard fileExtension == other.fileExtension else { return false }
        if let origin, let otherOrigin = other.origin {
            return origin.source == otherOrigin.source
                && origin.contentID == otherOrigin.contentID
                && quality == other.quality
        }
        return streamURL == other.streamURL
    }
}

/// An album, playlist or artist put on the watch whole — or the Songs
/// collection, which holds the tracks added one at a time. It lists its
/// tracks by key; the tracks themselves live once in `WatchLibrary.tracks`.
public struct WatchCollection: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case album, playlist, artist, songs
    }

    /// The key of the one Songs collection.
    public static let songsKey = "songs"

    public let key: String
    public let kind: Kind
    public var title: String
    public var subtitle: String
    public var artworkURL: URL?
    public let addedAt: Date
    public var trackKeys: [String]

    public var id: String { key }

    public init(
        key: String,
        kind: Kind,
        title: String,
        subtitle: String,
        artworkURL: URL? = nil,
        addedAt: Date,
        trackKeys: [String]
    ) {
        self.key = key
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.addedAt = addedAt
        self.trackKeys = trackKeys
    }
}

/// Everything on the watch, or on its way there. Either device changes it
/// — the iPhone from its menus, the watch from its own browsing — and every
/// change makes a new revision and goes to the other side whole; the
/// newest revision wins. The watch downloads what's new in it and deletes
/// what's gone. A whole library is small (a few hundred bytes a song), and
/// sending it whole means a transfer lost on the way is put right by the
/// next one.
public struct WatchLibrary: Codable, Equatable, Sendable {
    /// Grows with every change, and never goes back — it starts from the
    /// clock, so a reinstalled app on either side still outranks the other.
    public var revision: Int
    /// Newest first.
    public var collections: [WatchCollection]
    public var tracks: [String: WatchTrack]
    /// What songs come down at; nil until someone picks.
    public var quality: WatchDownloadQuality?

    public static let empty = WatchLibrary(revision: 0, collections: [], tracks: [:])

    public init(revision: Int, collections: [WatchCollection], tracks: [String: WatchTrack], quality: WatchDownloadQuality? = nil) {
        self.revision = revision
        self.collections = collections
        self.tracks = tracks
        self.quality = quality
    }

    /// What songs come down at: the chosen quality, or the recommended one.
    public var effectiveQuality: WatchDownloadQuality {
        quality ?? .recommended
    }

    public var isEmpty: Bool { collections.isEmpty }

    /// Every song some collection holds, in the order the watch fetches
    /// them: the newest collection first, each in its own order, a song in
    /// two collections once.
    public var wantedKeys: [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for collection in collections {
            for key in collection.trackKeys where tracks[key] != nil && seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }

    public func collection(key: String) -> WatchCollection? {
        collections.first { $0.key == key }
    }

    public func tracks(in collection: WatchCollection) -> [WatchTrack] {
        collection.trackKeys.compactMap { tracks[$0] }
    }

    /// Adds a collection, or replaces the one with its key, at the front,
    /// with its tracks as they are now (fresh stream URLs included).
    public mutating func upsert(_ collection: WatchCollection, tracks newTracks: [WatchTrack]) {
        collections.removeAll { $0.key == collection.key }
        collections.insert(collection, at: 0)
        for track in newTracks {
            tracks[track.key] = track
        }
        pruneTracks()
    }

    /// Adds songs to the Songs collection, newest first, making it if
    /// there's none yet. A song already in it moves to the top.
    public mutating func addSongs(_ newTracks: [WatchTrack], at date: Date) {
        guard !newTracks.isEmpty else { return }
        let added = newTracks.map(\.key)
        var songs = collection(key: WatchCollection.songsKey) ?? WatchCollection(
            key: WatchCollection.songsKey,
            kind: .songs,
            title: "Songs",
            subtitle: "",
            addedAt: date,
            trackKeys: []
        )
        songs.trackKeys = added + songs.trackKeys.filter { !added.contains($0) }
        songs.artworkURL = newTracks.first?.artworkURL ?? songs.artworkURL
        upsert(songs, tracks: newTracks)
    }

    public mutating func removeCollection(key: String) {
        collections.removeAll { $0.key == key }
        pruneTracks()
    }

    /// Takes a song out of the Songs collection, and the collection away
    /// once it's empty. A song an album also holds stays on the watch.
    public mutating func removeSong(key: String) {
        guard var songs = collection(key: WatchCollection.songsKey) else { return }
        songs.trackKeys.removeAll { $0 == key }
        if songs.trackKeys.isEmpty {
            removeCollection(key: WatchCollection.songsKey)
        } else if let index = collections.firstIndex(where: { $0.key == WatchCollection.songsKey }) {
            collections[index] = songs
            pruneTracks()
        }
    }

    /// Moves the revision on: one past the last, or the clock in
    /// milliseconds when that's further.
    public mutating func bumpRevision(now: Date = .now) {
        revision = max(revision + 1, Int(now.timeIntervalSince1970 * 1000))
    }

    /// Drops tracks no collection holds.
    private mutating func pruneTracks() {
        let held = Set(collections.flatMap(\.trackKeys))
        tracks = tracks.filter { held.contains($0.key) }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> WatchLibrary {
        try JSONDecoder().decode(WatchLibrary.self, from: data)
    }
}
