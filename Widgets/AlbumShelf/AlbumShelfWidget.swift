import AppIntents
import Defaults
import SwiftUI
import WidgetKit

/// A shelf of the listener's albums, every Home Screen size: the albums
/// played lately, those downloaded, or their own shelf (the albums they
/// added in Cue), as records, each sleeve standing on a dark shelf with
/// its record slid out, the one playing further, or as glass. It's the
/// book shelf's layout (`BookShelfWidgetView`), in rounded type.
///
/// Cue keeps the albums in the App Group (`AlbumShelfWidgetPublisher`,
/// `BookShelfWidgetState` in its `AlbumShelfWidget` folder) and reloads
/// the widget when they change; the widget only reads them. A tap plays an
/// album (`PlayAlbumIntent`, in Cue's process) or opens it, as the widget
/// is set.
struct AlbumShelfWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: BookShelfWidgetState.Albums.widgetKind, intent: AlbumShelfConfigurationIntent.self, provider: AlbumShelfProvider()) { entry in
            BookShelfWidgetView(entry: entry)
        }
        .configurationDisplayName("Albums")
        .description("Your albums on a shelf: play one again, the ones you've downloaded, or a shelf of your own.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }

    private static var families: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        #endif
        return families
    }
}

/// What an Albums widget shows and does, chosen in its Edit Widget sheet.
struct AlbumShelfConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Albums"
    static let description = IntentDescription("Shows a shelf of your albums.")

    @Parameter(title: "Shelf", default: .recentlyPlayed)
    var shelf: AlbumShelfOption

    /// My Shelf's albums, in the order chosen. No fixed size: with one
    /// (`size: 12`), Edit Widget showed twelve slots and no way to empty a
    /// filled one. The widget shows as many as it has room for.
    @Parameter(title: "Albums")
    var albums: [WidgetAlbum]?

    @Parameter(title: "Action", default: .playAlbum)
    var action: AlbumWidgetAction

    @Parameter(title: "Play in Background", description: "Plays without opening Cue.", default: true)
    var playsInBackground: Bool

    @Parameter(title: "Look", default: .records)
    var look: AlbumShelfLook

    /// Albums only for My Shelf; Play in Background only for Play Album.
    static var parameterSummary: some ParameterSummary {
        When(\.$shelf, .equalTo, .myShelf) {
            When(\.$action, .equalTo, .playAlbum) {
                Summary {
                    \.$shelf
                    \.$albums
                    \.$action
                    \.$playsInBackground
                    \.$look
                }
            } otherwise: {
                Summary {
                    \.$shelf
                    \.$albums
                    \.$action
                    \.$look
                }
            }
        } otherwise: {
            When(\.$action, .equalTo, .playAlbum) {
                Summary {
                    \.$shelf
                    \.$action
                    \.$playsInBackground
                    \.$look
                }
            } otherwise: {
                Summary {
                    \.$shelf
                    \.$action
                    \.$look
                }
            }
        }
    }
}

/// An album for Edit Widget's Albums, from every album Cue knows
/// (`BookShelfWidgetState.Catalog` in the album shelf's folder).
struct WidgetAlbum: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Album"
    static let defaultQuery = WidgetAlbumQuery()

    /// The album's key, as the shelves name it.
    let id: String
    let title: String
    let artist: String
    /// A cover on the web, for an album found in the Apple Music catalog
    /// that Cue hasn't written a small cover for.
    var artworkURL: URL?

    init(_ album: BookShelfWidgetState.Book) {
        id = album.id
        title = album.title
        artist = album.author
    }

    init(id: String, title: String, artist: String, artworkURL: URL?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
    }

    /// With its small cover, once Cue has written one, else the catalog's:
    /// read only as it's shown in Edit Widget's list.
    var displayRepresentation: DisplayRepresentation {
        let thumbnail = BookShelfWidgetState.Catalog.thumbnailURL(for: id, in: .albums).flatMap { try? Data(contentsOf: $0) }
        let image = thumbnail.map { DisplayRepresentation.Image(data: $0, isTemplate: false) }
            ?? artworkURL.map { DisplayRepresentation.Image(url: $0, isTemplate: false) }
        let subtitle = [artist, source].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
            image: image
        )
    }

    /// Where the album is, from its key's service: an album can be in more
    /// than one library ("21" in Plex, Apple Music and a Subsonic server),
    /// and without it the copies read the same.
    private var source: String? {
        if id.contains("|ondevice|") { return "Downloaded" }
        return switch id.split(separator: "|").first {
        case "plex": "Plex"
        case "apple": "Apple Music"
        case "subsonic": "Subsonic"
        case "files": "Files"
        default: nil
        }
    }

    /// What a slot is set to for nothing, offered first in the picker and
    /// left out by the widget: a way to empty a slot whatever Edit Widget
    /// offers for removing one.
    static let noAlbum = WidgetAlbum(id: "none", title: "No Album", artist: "", artworkURL: nil)

    var isNone: Bool {
        id == Self.noAlbum.id
    }

    var book: BookShelfWidgetState.Book {
        BookShelfWidgetState.Book(id: id, title: title, author: artist, fraction: nil, remaining: nil, duration: 0, isFinished: false, isDownloaded: false, cover: nil)
    }
}

/// The albums Edit Widget offers: those played lately and downloaded
/// first, then every album in the libraries, searchable by title or
/// artist, and, with Apple Music, its whole catalog as you search.
struct WidgetAlbumQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAlbum] {
        let state = BookShelfWidgetState.load(.albums)
        let known = Self.everyAlbum() + BookShelfWidgetState.Albums.Shelf.allCases.flatMap { state?.albums(on: $0) ?? [] }
        let albums = Dictionary(known.map { ($0.id, WidgetAlbum($0)) }, uniquingKeysWith: { first, _ in first })
        // One picked from the Apple Music catalog, not in a library and not
        // yet written by Cue: looked up again.
        let missing = identifiers.filter { albums[$0] == nil && $0 != WidgetAlbum.noAlbum.id }
        let found = Dictionary((await AppleMusicCatalog.albums(withIDs: missing)).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { $0 == WidgetAlbum.noAlbum.id ? WidgetAlbum.noAlbum : albums[$0] ?? found[$0] }
    }

    func entities(matching string: String) async throws -> IntentItemCollection<WidgetAlbum> {
        let query = string.trimmingCharacters(in: .whitespaces)
        let mine = Self.everyAlbum().filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.author.localizedStandardContains(query) }
        var sections: [IntentItemSection<WidgetAlbum>] = []
        if !mine.isEmpty {
            sections.append(IntentItemSection("Your Albums", items: mine.map { IntentItem(WidgetAlbum($0)) }))
        }
        if query.count >= 2 {
            let ids = Set(mine.map(\.id))
            let found = await AppleMusicCatalog.albums(matching: query).filter { !ids.contains($0.id) }
            if !found.isEmpty {
                sections.append(IntentItemSection("Apple Music", items: found.map { IntentItem($0) }))
            }
        }
        return IntentItemCollection(sections: sections)
    }

    func suggestedEntities() async throws -> IntentItemCollection<WidgetAlbum> {
        let state = BookShelfWidgetState.load(.albums)
        // First, for emptying a slot.
        var sections: [IntentItemSection<WidgetAlbum>] = [IntentItemSection(items: [IntentItem(WidgetAlbum.noAlbum)])]
        // Each album in one section only: Edit Widget lists an album once,
        // so those in a later section as well showed under none but it.
        var listed: Set<String> = []
        for (title, shelf) in [("Recently Played", BookShelfWidgetState.Albums.Shelf.recentlyPlayed), ("Downloaded", .downloaded)] {
            let albums = (state?.albums(on: shelf) ?? []).filter { listed.insert($0.id).inserted }
            if !albums.isEmpty {
                sections.append(IntentItemSection(LocalizedStringResource(stringLiteral: title), items: albums.map { IntentItem(WidgetAlbum($0)) }))
            }
        }
        let rest = Self.everyAlbum().filter { !listed.contains($0.id) }
        sections.append(IntentItemSection("All Albums", items: rest.map { IntentItem(WidgetAlbum($0)) }))
        return IntentItemCollection(sections: sections)
    }

    /// The catalog, else the shelves' albums before Cue has written one.
    static func everyAlbum() -> [BookShelfWidgetState.Book] {
        if let catalog = BookShelfWidgetState.Catalog.load(.albums), !catalog.books.isEmpty {
            return catalog.books
        }
        let state = BookShelfWidgetState.load(.albums) ?? .empty
        var seen: Set<String> = []
        return BookShelfWidgetState.Albums.Shelf.allCases
            .flatMap { state.albums(on: $0) }
            .filter { seen.insert($0.id).inserted }
    }
}

/// Apple Music's catalog, through Apple's public iTunes Search service,
/// which needs no sign-in, so the widget can ask it itself: its album ids
/// are Apple Music's, which Cue plays (`apple|<id>`). Only when Cue has
/// written the storefront (`Catalog.storefront`): with Apple Music on and
/// allowed.
enum AppleMusicCatalog {
    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let wrapperType: String?
        let collectionId: Int?
        let collectionName: String?
        let artistName: String?
        let artworkUrl100: String?
    }

    static func albums(matching query: String) async -> [WidgetAlbum] {
        await albums(path: "search", items: [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "25"),
        ])
    }

    static func albums(withIDs ids: [String]) async -> [WidgetAlbum] {
        let prefix = "apple|"
        let numbers = ids.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        guard !numbers.isEmpty else { return [] }
        return await albums(path: "lookup", items: [URLQueryItem(name: "id", value: numbers.joined(separator: ","))])
    }

    /// A few seconds at most: Edit Widget's search shows the listener's own
    /// albums only once this answers, and with no internet (Wi‑Fi with a
    /// LAN-only Plex) the default minute showed nothing at all.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration)
    }()

    private static func albums(path: String, items: [URLQueryItem]) async -> [WidgetAlbum] {
        guard let storefront = BookShelfWidgetState.Catalog.load(.albums)?.storefront,
              var components = URLComponents(string: "https://itunes.apple.com/\(path)") else { return [] }
        components.queryItems = items + [URLQueryItem(name: "country", value: storefront)]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return response.results.compactMap { result in
            guard result.wrapperType == "collection", let id = result.collectionId, let title = result.collectionName else { return nil }
            // The 100 px cover, asked for at 200 px for a sharp row.
            let artwork = result.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100", with: "200x200")) }
            return WidgetAlbum(id: "apple|\(id)", title: title, artist: result.artistName ?? "", artworkURL: artwork)
        }
    }
}

/// How the albums are drawn.
enum AlbumShelfLook: String, AppEnum, CaseIterable {
    /// Sleeves on a dark shelf, each with its record slid out.
    case records
    /// Rounded covers on frosted glass, no shelves, light or dark with the
    /// system.
    case glass

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Look"
    static let caseDisplayRepresentations: [AlbumShelfLook: DisplayRepresentation] = [
        .records: "Records",
        .glass: "Glass",
    ]
}

enum AlbumShelfOption: String, AppEnum, CaseIterable {
    case recentlyPlayed
    case downloaded
    /// The albums added in Cue, newest first.
    case myShelf

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shelf"
    static let caseDisplayRepresentations: [AlbumShelfOption: DisplayRepresentation] = [
        .recentlyPlayed: "Recently Played",
        .downloaded: "Downloaded",
        .myShelf: "My Shelf",
    ]

    var shelf: BookShelfWidgetState.Albums.Shelf {
        switch self {
        case .recentlyPlayed: .recentlyPlayed
        case .downloaded: .downloaded
        case .myShelf: .chosen
        }
    }

    var heading: ShelfHeading {
        let (title, symbol, empty): (String, String, String) = switch self {
        case .recentlyPlayed: ("Recently Played", "clock.arrow.circlepath", "The albums you play show up here.")
        case .downloaded: ("Downloaded", "arrow.down.circle", "Albums you download show up here.")
        case .myShelf: ("My Shelf", "opticaldisc", "Touch and hold, then Edit Widget to choose your albums and their order.")
        }
        return ShelfHeading(
            title: title,
            symbol: symbol,
            emptyMessage: empty,
            unwrittenTitle: "Your Albums",
            unwrittenMessage: "Open Cue to put your albums on this shelf.",
            appLink: BookShelfWidgetState.Albums.link(to: "", play: false).deletingQuery,
            // Albums chosen one by one name themselves.
            showsHeader: self != .myShelf
        )
    }
}

enum AlbumWidgetAction: String, AppEnum, CaseIterable {
    case playAlbum
    case openAlbum
    case openApp

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
    static let caseDisplayRepresentations: [AlbumWidgetAction: DisplayRepresentation] = [
        .playAlbum: "Play Album",
        .openAlbum: "Open Album",
        .openApp: "Open App",
    ]

    var action: ShelfAction {
        switch self {
        case .playAlbum: .play
        case .openAlbum: .open
        case .openApp: .openApp
        }
    }
}

private extension URL {
    /// The link without its query: `cue://album`, which opens Cue.
    var deletingQuery: URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.queryItems = nil
        return components?.url ?? self
    }
}

struct AlbumShelfProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BookShelfEntry {
        Self.entry(for: AlbumShelfConfigurationIntent(), state: .sampleAlbums, albums: BookShelfWidgetState.sampleAlbums.albums(on: .recentlyPlayed))
    }

    func snapshot(for configuration: AlbumShelfConfigurationIntent, in context: Context) async -> BookShelfEntry {
        entry(for: configuration, in: context)
    }

    /// One entry, kept until Cue says something changed.
    func timeline(for configuration: AlbumShelfConfigurationIntent, in context: Context) async -> Timeline<BookShelfEntry> {
        Timeline(entries: [entry(for: configuration, in: context)], policy: .never)
    }

    private func entry(for configuration: AlbumShelfConfigurationIntent, in context: Context) -> BookShelfEntry {
        let state = BookShelfWidgetState.load(.albums)
        // The gallery shows made-up records until there are some on the shelf.
        if context.isPreview, configuration.shelf != .myShelf, state?.albums(on: configuration.shelf.shelf).isEmpty != false {
            return Self.entry(for: configuration, state: .sampleAlbums, albums: BookShelfWidgetState.sampleAlbums.albums(on: configuration.shelf.shelf))
        }
        guard configuration.shelf == .myShelf else {
            return Self.entry(for: configuration, state: state ?? .empty, albums: state?.albums(on: configuration.shelf.shelf) ?? [], isUnwritten: state == nil)
        }
        let chosen = (configuration.albums ?? []).filter { !$0.isNone }
        if !context.isPreview, !chosen.isEmpty {
            // For Cue to write their covers and which one plays.
            BookShelfWidgetState.noteChosen(chosen.map(\.id), in: .albums)
        }
        return Self.entry(for: configuration, state: state ?? .empty, albums: chosen.map { Self.written($0, in: state) })
    }

    private static func entry(for configuration: AlbumShelfConfigurationIntent, state: BookShelfWidgetState, albums: [BookShelfWidgetState.Book], isUnwritten: Bool = false) -> BookShelfEntry {
        let style = ShelfStyle(
            kind: .albums,
            look: configuration.look == .glass ? .glass : .records,
            action: configuration.action.action,
            playsInBackground: configuration.playsInBackground,
            showsProgress: false
        )
        return BookShelfEntry(
            date: .now,
            state: state,
            books: albums,
            style: style,
            heading: configuration.shelf.heading,
            isUnwritten: isUnwritten
        )
    }

    /// `album` as Cue wrote it on any shelf (the Chosen shelf has its cover
    /// once Cue has heard of it), else as it was picked.
    private static func written(_ album: WidgetAlbum, in state: BookShelfWidgetState?) -> BookShelfWidgetState.Book {
        let shelves = [BookShelfWidgetState.Albums.Shelf.chosen] + BookShelfWidgetState.Albums.Shelf.allCases.filter { $0 != .chosen }
        for shelf in shelves {
            if let written = state?.albums(on: shelf).first(where: { $0.id == album.id }) {
                return written
            }
        }
        return album.book
    }
}

// MARK: - The gallery's records

extension BookShelfWidgetState {
    /// What the widget gallery shows: made-up albums with covers drawn for
    /// them (`GeneratedCover`), the first playing.
    static let sampleAlbums: BookShelfWidgetState = {
        let albums = [
            ("Northern Lights", "The Quiet Hours"),
            ("Paper Moons", "Ada Vale"),
            ("Slow Tide", "Harbour Lights"),
            ("Glass Houses", "Mira North"),
            ("Late Bloom", "The Fieldnotes"),
            ("Static Hearts", "Juniper Lane"),
            ("Open Road", "Calloway"),
            ("Blue Hour", "Sol & Wren"),
            ("Small Victories", "Kestrel"),
            ("Afterglow", "The Low Suns"),
            ("Undertow", "Marlowe"),
            ("Wildflower Year", "Ivy Bell"),
        ].enumerated().map { index, album in
            Book(id: "sample-album|\(index)", title: album.0, author: album.1, fraction: nil, remaining: nil, duration: 0, isFinished: false, isDownloaded: false, cover: nil)
        }
        return BookShelfWidgetState(
            shelves: [
                Albums.Shelf.recentlyPlayed.rawValue: albums,
                Albums.Shelf.downloaded.rawValue: Array(albums.reversed()),
                Albums.Shelf.chosen.rawValue: Array(albums.dropFirst(4) + albums.prefix(4)),
            ],
            loadedID: albums[0].id,
            isPlaying: true,
            chapter: nil,
            needsServer: false
        )
    }()
}
