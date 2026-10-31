import Foundation

/// An artist's releases for the discography widget, newest first: an Apple
/// Music artist's as the widget last read them from Apple's public catalog,
/// a Plex artist's as Cue last wrote them (only Cue can reach the server).
/// One file an artist in the App Group's `DiscographyWidget` folder, its
/// covers and photo beside it, all named for the artist (`coverPrefix`).
public struct DiscographyArtist: Codable, Equatable, Sendable {
    public struct Release: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// The album's key, as the album shelf's Play and links name it
        /// (`apple|<catalog id>`, `plex|<id>`).
        public var id: String
        public var title: String
        /// When it came out, or comes out (a pre-release); nil when unknown.
        public var released: Date?
        /// The cover's file in the folder; nil until one is written.
        public var cover: String?
        /// Where the cover is, for one written only once it's shown.
        public var artwork: URL?

        public init(id: String, title: String, released: Date?, cover: String?, artwork: URL? = nil) {
            self.id = id
            self.title = title
            self.released = released
            self.cover = cover
            self.artwork = artwork
        }

        /// Out within `newFor`, or not out yet.
        public func isNew(at date: Date = .now) -> Bool {
            guard let released else { return false }
            return date.timeIntervalSince(released) < DiscographyArtist.newFor
        }

        public func isUpcoming(at date: Date = .now) -> Bool {
            released.map { $0 > date } ?? false
        }
    }

    /// The artist's key: `apple|<catalog id>` or `plex|<id>`.
    public var id: String
    public var name: String
    /// The artist's photo's file in the folder.
    public var photo: String?
    public var releases: [Release]
    /// When the releases were read.
    public var readAt: Date

    public init(id: String, name: String, photo: String?, releases: [Release], readAt: Date) {
        self.id = id
        self.name = name
        self.photo = photo
        self.releases = releases
        self.readAt = readAt
    }

    /// How long a release counts as new.
    public static let newFor: TimeInterval = 90 * 24 * 3600
    /// What the app hands `WidgetCenter` to reload.
    public static let widgetKind = "dance.cue.discography"

    // MARK: - The files

    public static var directory: URL? {
        BookShelfWidgetState.directory(.discography)
    }

    private static func fileURL(for id: String) -> URL? {
        directory?.appendingPathComponent("\(BookShelfWidgetState.coverPrefix(for: id))artist.json")
    }

    /// Every artist kept, for the widget gallery to show one.
    public static func kept() -> [DiscographyArtist] {
        guard let directory else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix("artist.json") }.compactMap { file in
            (try? Data(contentsOf: directory.appendingPathComponent(file))).flatMap { try? JSONDecoder().decode(DiscographyArtist.self, from: $0) }
        }
    }

    public static func load(id: String) -> DiscographyArtist? {
        guard let url = fileURL(for: id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DiscographyArtist.self, from: data)
    }

    /// Writes the artist, then takes away the covers of releases it no
    /// longer lists. Not those of releases it lists without a cover: two
    /// widgets of one artist write covers each (the albums each shows), and
    /// one saving over the other mustn't delete what the other wrote.
    public func save() throws {
        guard let directory = Self.directory, let url = Self.fileURL(for: id) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        let prefix = BookShelfWidgetState.coverPrefix(for: id)
        let artwork = releases.compactMap { $0.artwork.map { Self.imageName(for: id, source: $0.absoluteString) } }
        let named = Set(releases.compactMap(\.cover) + artwork + [photo].compactMap(\.self))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix(prefix) && file.hasSuffix(".jpg") && !named.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// Takes away the files of artists no widget is set to (`keeping`)
    /// that haven't been read for `age`: an artist a widget showed once, or
    /// the gallery did.
    public static func removeUnused(keeping ids: Set<String>, olderThan age: TimeInterval) {
        guard let directory else { return }
        let unused = kept().filter { !ids.contains($0.id) && Date.now.timeIntervalSince($0.readAt) > age }
        guard !unused.isEmpty else { return }
        let prefixes = unused.map { BookShelfWidgetState.coverPrefix(for: $0.id) }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where prefixes.contains(where: file.hasPrefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: - Apple's albums

    /// Apple Music's own list of an artist's albums (the Albums shelf in
    /// Music, MusicKit's `fullAlbums`: no compilations, live albums, singles
    /// or EPs), by catalog id, which Cue writes for Studio Albums: the public
    /// catalog the widget reads says none of that.
    public struct AlbumList: Codable, Equatable, Sendable {
        public var ids: [String]
        public var readAt: Date

        public init(ids: [String], readAt: Date) {
            self.ids = ids
            self.readAt = readAt
        }
    }

    private static func albumListURL(for id: String) -> URL? {
        directory?.appendingPathComponent("\(BookShelfWidgetState.coverPrefix(for: id))albums.json")
    }

    public static func albumList(for id: String) -> AlbumList? {
        guard let url = albumListURL(for: id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AlbumList.self, from: data)
    }

    public static func save(_ list: AlbumList, for id: String) throws {
        guard let directory, let url = albumListURL(for: id) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(list).write(to: url, options: .atomic)
    }

    /// The file for one of `artistID`'s images from `source`: a new
    /// picture is a new name, so a widget never shows one half written.
    public static func imageName(for artistID: String, source: String) -> String {
        "\(BookShelfWidgetState.coverPrefix(for: artistID))\(BookShelfWidgetState.stableHash(source)).jpg"
    }

    public static func imageURL(named name: String) -> URL? {
        directory?.appendingPathComponent(name)
    }
}
