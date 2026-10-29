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

    public init(shelves: [String: [Book]], loadedID: String?, isPlaying: Bool, chapter: String?, needsServer: Bool) {
        self.shelves = shelves
        self.loadedID = loadedID
        self.isPlaying = isPlaying
        self.chapter = chapter
        self.needsServer = needsServer
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

    /// The widget's folder in the App Group: the state and the covers.
    public static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupStorageKeys.name)?
            .appendingPathComponent("BookShelfWidget", isDirectory: true)
    }

    private static var fileURL: URL? {
        directory?.appendingPathComponent("State.json")
    }

    /// What the app last wrote; nil when it hasn't written yet.
    public static func load() -> BookShelfWidgetState? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BookShelfWidgetState.self, from: data)
    }

    public func save() throws {
        guard let directory = Self.directory, let url = Self.fileURL else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// Where the cover named `name` is kept.
    public static func coverURL(named name: String) -> URL? {
        directory?.appendingPathComponent(name)
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
        guard url.scheme == "cue", url.host?.lowercased() == "audiobook",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty else { return nil }
        return (id, items.contains { $0.name == "play" && $0.value == "1" })
    }
}
