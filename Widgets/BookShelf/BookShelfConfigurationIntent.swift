import AppIntents
import Defaults
import WidgetKit

/// What a book shelf widget shows and does, chosen in its Edit Widget sheet.
struct BookShelfConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Book Shelf"
    static let description = IntentDescription("Shows a shelf of your audiobooks.")

    @Parameter(title: "Shelf", default: .continueListening)
    var shelf: BookShelfOption

    /// The book a widget set to One Book shows.
    @Parameter(title: "Book")
    var book: WidgetBook?

    @Parameter(title: "Action", default: .playBook)
    var action: BookWidgetAction

    @Parameter(title: "Play in Background", description: "Plays without opening Cue.", default: true)
    var playsInBackground: Bool

    @Parameter(title: "Look", default: .bookshelf)
    var look: BookShelfLook

    @Parameter(title: "Show Progress", default: true)
    var showsProgress: Bool

    /// Book only for One Book; Play in Background only for Play Book; Look
    /// only where there are shelves to draw, not the one cover of a small
    /// widget or the Lock Screen's.
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .oneOf, [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]) {
            When(\.$shelf, .equalTo, .book) {
                When(\.$action, .equalTo, .playBook) {
                    Summary {
                        \.$shelf
                        \.$book
                        \.$action
                        \.$playsInBackground
                        \.$showsProgress
                    }
                } otherwise: {
                    Summary {
                        \.$shelf
                        \.$book
                        \.$action
                        \.$showsProgress
                    }
                }
            } otherwise: {
                When(\.$action, .equalTo, .playBook) {
                    Summary {
                        \.$shelf
                        \.$action
                        \.$playsInBackground
                        \.$showsProgress
                    }
                } otherwise: {
                    Summary {
                        \.$shelf
                        \.$action
                        \.$showsProgress
                    }
                }
            }
        } otherwise: {
            When(\.$shelf, .equalTo, .book) {
                When(\.$action, .equalTo, .playBook) {
                    Summary {
                        \.$shelf
                        \.$book
                        \.$action
                        \.$playsInBackground
                        \.$look
                        \.$showsProgress
                    }
                } otherwise: {
                    Summary {
                        \.$shelf
                        \.$book
                        \.$action
                        \.$look
                        \.$showsProgress
                    }
                }
            } otherwise: {
                When(\.$action, .equalTo, .playBook) {
                    Summary {
                        \.$shelf
                        \.$action
                        \.$playsInBackground
                        \.$look
                        \.$showsProgress
                    }
                } otherwise: {
                    Summary {
                        \.$shelf
                        \.$action
                        \.$look
                        \.$showsProgress
                    }
                }
            }
        }
    }
}

/// A book for Edit Widget's Book, from every book Cue knows
/// (`BookShelfWidgetState.Catalog`).
struct WidgetBook: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Book"
    static let defaultQuery = WidgetBookQuery()

    /// The book's key, as the shelves name it.
    let id: String
    let title: String
    let author: String

    init(_ book: BookShelfWidgetState.Book) {
        id = book.id
        title = book.title
        author = book.author
    }

    /// With its small cover, once Cue has written one: read only as it's
    /// shown in Edit Widget's list, not each time the widget draws.
    var displayRepresentation: DisplayRepresentation {
        let thumbnail = BookShelfWidgetState.Catalog.thumbnailURL(for: id).flatMap { try? Data(contentsOf: $0) }
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: author.isEmpty ? nil : "\(author)",
            image: thumbnail.map { DisplayRepresentation.Image(data: $0, isTemplate: false) }
        )
    }
}

/// The books Edit Widget offers: those being listened to first, then every
/// book, searchable by title or author.
struct WidgetBookQuery: EntityStringQuery {
    /// Always a book for each id: from the catalog, the shelves Cue wrote
    /// (the Chosen shelf has the book a widget is set to), else a stand-in,
    /// so a One Book widget keeps its book while the catalog lacks it (an
    /// Audiobookshelf book offline): one it couldn't find, it lost.
    func entities(for identifiers: [String]) async throws -> [WidgetBook] {
        let state = BookShelfWidgetState.load()
        let known = Self.everyBook() + BookShelfWidgetState.Shelf.allCases.flatMap { state?.books(on: $0) ?? [] }
        return identifiers.map { id in
            known.first { $0.id == id }.map(WidgetBook.init)
                ?? WidgetBook(BookShelfWidgetState.Book(id: id, title: "Book", author: "", fraction: nil, remaining: nil, duration: 0, isFinished: false, isDownloaded: false, cover: nil))
        }
    }

    func entities(matching string: String) async throws -> IntentItemCollection<WidgetBook> {
        let query = string.trimmingCharacters(in: .whitespaces)
        let books = Self.everyBook().filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.author.localizedStandardContains(query) }
        return IntentItemCollection(items: books.map(WidgetBook.init))
    }

    func suggestedEntities() async throws -> IntentItemCollection<WidgetBook> {
        let listening = BookShelfWidgetState.load()?.books(on: .continueListening) ?? []
        var sections: [IntentItemSection<WidgetBook>] = []
        if !listening.isEmpty {
            sections.append(IntentItemSection("Continue Listening", items: listening.map { IntentItem(WidgetBook($0)) }))
        }
        // Each book in one section only: Edit Widget lists a book once.
        let listed = Set(listening.map(\.id))
        sections.append(IntentItemSection("All Books", items: Self.everyBook().filter { !listed.contains($0.id) }.map { IntentItem(WidgetBook($0)) }))
        return IntentItemCollection(sections: sections)
    }

    /// The catalog, else the shelves' books before Cue has written one.
    private static func everyBook() -> [BookShelfWidgetState.Book] {
        if let catalog = BookShelfWidgetState.Catalog.load(), !catalog.books.isEmpty {
            return catalog.books
        }
        let state = BookShelfWidgetState.load() ?? .empty
        var seen: Set<String> = []
        return BookShelfWidgetState.Shelf.allCases
            .flatMap { state.books(on: $0) }
            .filter { seen.insert($0.id).inserted }
    }
}

/// The Audiobooks tab's shelves a widget can show, or one book of any.
enum BookShelfOption: String, AppEnum, CaseIterable {
    case continueListening
    case recentlyAdded
    case downloaded
    case finished
    /// The book chosen in `book`.
    case book

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shelf"
    static let caseDisplayRepresentations: [BookShelfOption: DisplayRepresentation] = [
        .continueListening: "Continue Listening",
        .recentlyAdded: "Recently Added",
        .downloaded: "Downloaded",
        .finished: "Finished",
        .book: "One Book",
    ]

    var shelf: BookShelfWidgetState.Shelf {
        switch self {
        case .continueListening: .continueListening
        case .recentlyAdded: .recentlyAdded
        case .downloaded: .downloaded
        case .finished: .finished
        case .book: .chosen
        }
    }

    var title: String {
        switch self {
        case .continueListening: "Continue Listening"
        case .recentlyAdded: "Recently Added"
        case .downloaded: "Downloaded"
        case .finished: "Finished"
        case .book: "Audiobook"
        }
    }

    /// The mark beside its name.
    var symbol: String {
        switch self {
        case .continueListening: "headphones"
        case .recentlyAdded: "sparkles"
        case .downloaded: "arrow.down.circle"
        case .finished: "checkmark.circle"
        case .book: "book.closed"
        }
    }

    /// What an empty shelf says.
    var emptyMessage: String {
        switch self {
        case .continueListening: "The books you're listening to wait here."
        case .recentlyAdded: "The newest books on your servers show up here."
        case .downloaded: "Books you download show up here."
        case .finished: "Books you finish show up here."
        case .book: "Touch and hold, then Edit Widget to choose a book."
        }
    }
}

/// What a tap on a book does.
enum BookWidgetAction: String, AppEnum, CaseIterable {
    case playBook
    case openBook
    case openApp

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
    static let caseDisplayRepresentations: [BookWidgetAction: DisplayRepresentation] = [
        .playBook: "Play Book",
        .openBook: "Open Book",
        .openApp: "Open App",
    ]
}

/// How the shelves are drawn.
enum BookShelfLook: String, AppEnum, CaseIterable {
    /// Covers standing on walnut shelves.
    case bookshelf
    /// Flat: rounded covers on frosted glass, no shelves, light or dark
    /// with the system.
    case glass

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Look"
    static let caseDisplayRepresentations: [BookShelfLook: DisplayRepresentation] = [
        .bookshelf: "Bookshelf",
        .glass: "Glass",
    ]
}
