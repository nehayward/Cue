import Foundation

/// What the book shelf widget shows, as Cue last left it in the App Group:
/// each shelf's books (Continue Listening, Recently Added, Downloaded,
/// Finished) with how far into each the listener is, and the book loaded
/// to play. The app writes it, with each book's cover beside it, when any
/// of that changes, and asks WidgetKit to reload; the widget only reads.
///
/// A file in the group's container rather than the group's defaults: a
/// defaults write in the app reaches every view holding `@AppStorage`.
public struct BookShelfWidgetState: Codable, Equatable, Sendable {
    /// The shelves a widget can be set to show.
    public enum Shelf: String, Codable, CaseIterable, Sendable {
        case continueListening
        case recentlyAdded
        case downloaded
        case finished
        /// The books widgets are set to show one of (`chosenBookIDs`),
        /// whichever shelf they're on, if any.
        case chosen
    }

    public struct Book: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// The book's service and id, as `AudiobookProgressStore` keys it.
        public var id: String
        public var title: String
        public var author: String
        /// How much has been heard, 0–1; nil before it's started, or with
        /// no length to measure against.
        public var fraction: Double?
        /// What's left to hear at 1×, once it's started.
        public var remaining: TimeInterval?
        /// The book's length; zero when it isn't known.
        public var duration: TimeInterval
        public var isFinished: Bool
        /// Whole on this device: it plays with no network.
        public var isDownloaded: Bool
        /// The cover's file in `directory`; nil until one is written.
        public var cover: String?

        public init(id: String, title: String, author: String, fraction: Double?, remaining: TimeInterval?, duration: TimeInterval, isFinished: Bool, isDownloaded: Bool, cover: String?) {
            self.id = id
            self.title = title
            self.author = author
            self.fraction = fraction
            self.remaining = remaining
            self.duration = duration
            self.isFinished = isFinished
            self.isDownloaded = isDownloaded
            self.cover = cover
        }
    }

    /// Each shelf's books by `Shelf.rawValue`, in the order the app shows them.
    public var shelves: [String: [Book]]
    /// The book loaded to play, playing or paused.
    public var loadedID: String?
    public var isPlaying: Bool
    /// The chapter the loaded book is in, when it has chapters.
    public var chapter: String?
    /// No server for books is set up and none is on this device: the
    /// widget says where to set one up rather than showing empty shelves.
    public var needsServer: Bool
    /// The Sonos group Play goes to, by name; nil for this device.
    public var speaker: String?
    /// The album the player's song is from, on a shelf or not, by key, and
    /// whether it's playing: the album shelf writes it for the discography
    /// widget, whose albums Cue doesn't keep.
    public var albumInPlayer: String?
    public var albumInPlayerIsPlaying: Bool?

    public init(shelves: [String: [Book]], loadedID: String?, isPlaying: Bool, chapter: String?, needsServer: Bool, speaker: String? = nil, albumInPlayer: String? = nil, albumInPlayerIsPlaying: Bool? = nil) {
        self.shelves = shelves
        self.loadedID = loadedID
        self.isPlaying = isPlaying
        self.chapter = chapter
        self.needsServer = needsServer
        self.speaker = speaker
        self.albumInPlayer = albumInPlayer
        self.albumInPlayerIsPlaying = albumInPlayerIsPlaying
    }

    public static let empty = BookShelfWidgetState(shelves: [:], loadedID: nil, isPlaying: false, chapter: nil, needsServer: false)

    public func books(on shelf: Shelf) -> [Book] {
        shelves[shelf.rawValue] ?? []
    }

    /// Whether `book` is the one loaded and it's playing.
    public func isPlaying(_ book: Book) -> Bool {
        isPlaying && loadedID == book.id
    }

    /// What the app hands `WidgetCenter` to reload.
    public static let widgetKind = "dance.cue.bookshelf"

    // MARK: - The file

    /// Which widget's folder in the App Group: the book shelf's, or the
    /// album shelf's, which keeps its albums in the same shape (an album's
    /// artist as `author`, no place).
    public enum Folder: String, Sendable {
        case books = "BookShelfWidget"
        case albums = "AlbumShelfWidget"
        /// The discography widget's artists (`DiscographyArtist`), and
        /// Plex's artists for its Edit Widget (`Catalog`).
        case discography = "DiscographyWidget"
    }

    /// The widget's folder in the App Group: the state and the covers.
    public static var directory: URL? {
        directory(.books)
    }

    public static func directory(_ folder: Folder) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupStorageKeys.name)?
            .appendingPathComponent(folder.rawValue, isDirectory: true)
    }

    /// What the app last wrote; nil when it hasn't written yet.
    public static func load(_ folder: Folder = .books) -> BookShelfWidgetState? {
        guard let url = directory(folder)?.appendingPathComponent("State.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BookShelfWidgetState.self, from: data)
    }

    public func save(_ folder: Folder = .books) throws {
        guard let directory = Self.directory(folder) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("State.json"), options: .atomic)
    }

    /// Where the cover named `name` is kept.
    public static func coverURL(named name: String, in folder: Folder = .books) -> URL? {
        directory(folder)?.appendingPathComponent(name)
    }

    /// The file name for `bookID`'s cover from `source` at `pixels` wide:
    /// a new cover, or a new size of it, is a new name, so a widget never
    /// shows a file half written over the one it had.
    public static func coverName(for bookID: String, source: String, pixels: Int) -> String {
        "\(coverPrefix(for: bookID))\(stableHash("\(source)|\(pixels)")).jpg"
    }

    /// What every cover file of `bookID`'s starts with.
    public static func coverPrefix(for bookID: String) -> String {
        let safe = bookID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return "\(safe.suffix(60))-"
    }

    /// FNV-1a, as hex: `Hasher` changes from launch to launch.
    static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Every book

    /// Every book (or album) Cue knows, for Edit Widget's Book (or
    /// Albums): the shelves' items, and every server's whole library, the
    /// order Edit Widget lists them in. Only what names one (its key, title
    /// and author or artist): how far in and the cover come with the
    /// Chosen shelf, which Cue writes once it hears a widget was set to it.
    public struct Catalog: Codable, Equatable, Sendable {
        public var books: [Book]
        /// The Apple Music storefront (a country code) the album shelf's
        /// Edit Widget searches the catalog of, beyond the libraries; nil
        /// without Apple Music, and for books.
        public var storefront: String?
        /// When the items were read, for a catalog read now and then.
        public var readAt: Date?
        /// The server they were read from, for one server's list (Plex's
        /// artists): a list from another isn't held to its size.
        public var server: String?

        public init(books: [Book], storefront: String? = nil, readAt: Date? = nil, server: String? = nil) {
            self.books = books
            self.storefront = storefront
            self.readAt = readAt
            self.server = server
        }

        private static func fileURL(_ folder: Folder) -> URL? {
            directory(folder)?.appendingPathComponent("Catalog.json")
        }

        public static func load(_ folder: Folder = .books) -> Catalog? {
            guard let url = fileURL(folder), let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Catalog.self, from: data)
        }

        public func save(_ folder: Folder = .books) throws {
            guard let directory = BookShelfWidgetState.directory(folder), let url = Self.fileURL(folder) else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        }

        /// Where each catalog item's small cover is kept, for Edit Widget's
        /// list: one an item, written once.
        public static func thumbnailDirectory(_ folder: Folder = .books) -> URL? {
            directory(folder)?.appendingPathComponent("Thumbnails", isDirectory: true)
        }

        public static func thumbnailURL(for id: String, in folder: Folder = .books) -> URL? {
            thumbnailDirectory(folder)?.appendingPathComponent("\(coverPrefix(for: id))\(stableHash(id)).jpg")
        }
    }

    // MARK: - The books widgets are set to

    /// How long a book a widget named stays chosen without the widget
    /// naming it again: each reload names it, and Cue reloads the widget
    /// whenever it writes, so only a widget changed or taken away lets go.
    private static let chosenLifetime: TimeInterval = 14 * 24 * 3600

    private static func chosenURL(_ folder: Folder) -> URL? {
        directory(folder)?.appendingPathComponent("Chosen.json")
    }

    private static func loadChosen(_ folder: Folder) -> [String: Date] {
        guard let url = chosenURL(folder), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    /// Called by the widget as it draws the items it's set to: Cue reads
    /// them back (`chosenBookIDs()`) to write their place and cover.
    /// Written only when one is new to it or a day has passed.
    public static func noteChosen(_ ids: [String], in folder: Folder = .books) {
        var chosen = loadChosen(folder)
        let fresh = ids.filter { id in chosen[id].map { Date.now.timeIntervalSince($0) >= 24 * 3600 } ?? true }
        guard !fresh.isEmpty else { return }
        for id in fresh {
            chosen[id] = .now
        }
        chosen = chosen.filter { Date.now.timeIntervalSince($0.value) < chosenLifetime }
        guard let directory = directory(folder), let url = chosenURL(folder), let data = try? JSONEncoder().encode(chosen) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// The items widgets were set to lately, by key.
    public static func chosenBookIDs(in folder: Folder = .books) -> Set<String> {
        Set(loadChosen(folder).filter { Date.now.timeIntervalSince($0.value) < chosenLifetime }.keys)
    }

    // MARK: - Links

    /// Opens the Audiobooks tab.
    public static let audiobooksLink = URL(string: "cue://audiobooks")!

    /// Opens `bookID`'s page, or plays it and opens the player.
    public static func link(to bookID: String, play: Bool) -> URL {
        var components = URLComponents()
        components.scheme = "cue"
        components.host = "audiobook"
        components.queryItems = [URLQueryItem(name: "id", value: bookID)] + (play ? [URLQueryItem(name: "play", value: "1")] : [])
        return components.url ?? audiobooksLink
    }

    /// The book a `link(to:play:)` names, and whether it asks to play it.
    public static func book(in url: URL) -> (id: String, play: Bool)? {
        item(in: url, host: "audiobook")
    }

    private static func item(in url: URL, host: String) -> (id: String, play: Bool)? {
        guard url.scheme == "cue", url.host?.lowercased() == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty else { return nil }
        return (id, items.contains { $0.name == "play" && $0.value == "1" })
    }

    // MARK: - The album shelf

    /// The album shelf widget's: its kind, its shelves, and its links.
    public enum Albums {
        public static let widgetKind = "dance.cue.albumshelf"

        /// The album shelf's shelves, by the keys its state keeps them under.
        public enum Shelf: String, CaseIterable, Sendable {
            case recentlyPlayed
            case downloaded
            /// The albums widgets are set to (My Shelf), whichever shelf
            /// they're on, if any.
            case chosen
        }

        /// Opens the album's page, or plays it and opens the player.
        public static func link(to albumID: String, play: Bool) -> URL {
            var components = URLComponents()
            components.scheme = "cue"
            components.host = "album"
            components.queryItems = [URLQueryItem(name: "id", value: albumID)] + (play ? [URLQueryItem(name: "play", value: "1")] : [])
            return components.url ?? URL(string: "cue://")!
        }

        /// The album a `link(to:play:)` names, and whether it asks to play it.
        public static func album(in url: URL) -> (id: String, play: Bool)? {
            BookShelfWidgetState.item(in: url, host: "album")
        }
    }

    public func albums(on shelf: Albums.Shelf) -> [Book] {
        shelves[shelf.rawValue] ?? []
    }
}
