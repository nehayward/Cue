import Foundation

/// A song the watch keeps: what it shows, and the URL it downloads the file
/// from — a Plex or Subsonic stream as the iPhone's Streaming Quality
/// delivers it, self-authenticating, so the watch needs no account of its
/// own. `key` is the iPhone's download key (`DownloadNaming`): stable per
/// track and safe as a file name, so a song in two albums is one file.
public struct WatchTrack: Codable, Hashable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let streamURL: URL
    public let fileExtension: String
    public let duration: TimeInterval?

    public var id: String { key }

    public init(
        key: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        streamURL: URL,
        fileExtension: String,
        duration: TimeInterval? = nil
    ) {
        self.key = key
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.streamURL = streamURL
        self.fileExtension = fileExtension
        self.duration = duration
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

/// Everything the iPhone has put on the watch. The iPhone owns it: every
/// change there makes a new revision and sends it whole, and the watch
/// downloads what's new in it and deletes what's gone. A whole library is
/// small (a few hundred bytes a song), and sending it whole means a
/// transfer lost on the way is put right by the next one.
public struct WatchLibrary: Codable, Equatable, Sendable {
    /// Grows with every change, and never goes back — it starts from the
    /// clock, so a reinstalled iPhone app still outranks what the watch has.
    public var revision: Int
    /// Newest first.
    public var collections: [WatchCollection]
    public var tracks: [String: WatchTrack]

    public static let empty = WatchLibrary(revision: 0, collections: [], tracks: [:])

    public init(revision: Int, collections: [WatchCollection], tracks: [String: WatchTrack]) {
        self.revision = revision
        self.collections = collections
        self.tracks = tracks
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
