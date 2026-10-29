import AppIntents
import Defaults
import SwiftUI
import WidgetKit

/// A shelf of the listener's audiobooks, every size: one book's cover on a
/// small widget, a shelf of them on a medium, the book on the go on display
/// above more shelves on a large and on iOS 27's page-tall iPhone widget,
/// and a wide bookcase on an iPad's extra large. Each looks like a walnut
/// bookshelf or a record shelf, the records slid out of their sleeves.
///
/// Cue keeps the shelves it shows in the App Group
/// (`BookShelfWidgetState`, written by `BookShelfWidgetPublisher`) and
/// reloads the widget when they change; the widget only reads them. A tap
/// plays a book where it was left (`PlayBookIntent`, in Cue's process),
/// opens its page, or opens Cue, as the widget is set.
struct BookShelfWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: BookShelfWidgetState.widgetKind, intent: BookShelfConfigurationIntent.self, provider: BookShelfProvider()) { entry in
            BookShelfWidgetView(entry: entry)
        }
        .configurationDisplayName("Book Shelf")
        .description("Your audiobooks on a shelf: pick up where you left off, or start the next one.")
        .supportedFamilies(Self.families)
        // The shelves run edge to edge; the views keep the system's margins
        // themselves (`widgetContentMargins`).
        .contentMarginsDisabled()
    }

    private static var families: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ]
        #if !targetEnvironment(macCatalyst)
        // iOS 27's iPhone widget a Home Screen page tall.
        if #available(iOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        #endif
        return families
    }
}

struct BookShelfEntry: TimelineEntry {
    let date: Date
    let configuration: BookShelfConfigurationIntent
    let state: BookShelfWidgetState
    /// Cue hasn't written its shelves yet (not opened since it was
    /// installed or updated).
    var isUnwritten = false

    var books: [BookShelfWidgetState.Book] {
        state.books(on: configuration.shelf.shelf)
    }

    /// Up the Smart Stack while a book on the shelf plays.
    var relevance: TimelineEntryRelevance? {
        books.contains { state.isPlaying($0) } ? TimelineEntryRelevance(score: 80) : nil
    }
}

struct BookShelfProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BookShelfEntry {
        BookShelfEntry(date: .now, configuration: BookShelfConfigurationIntent(), state: .sample)
    }

    func snapshot(for configuration: BookShelfConfigurationIntent, in context: Context) async -> BookShelfEntry {
        entry(for: configuration, in: context)
    }

    /// One entry, kept until Cue says something changed.
    func timeline(for configuration: BookShelfConfigurationIntent, in context: Context) async -> Timeline<BookShelfEntry> {
        Timeline(entries: [entry(for: configuration, in: context)], policy: .never)
    }

    private func entry(for configuration: BookShelfConfigurationIntent, in context: Context) -> BookShelfEntry {
        let state = BookShelfWidgetState.load()
        // The gallery shows made-up books until there are some on the shelf.
        if context.isPreview, state?.books(on: configuration.shelf.shelf).isEmpty != false {
            return BookShelfEntry(date: .now, configuration: configuration, state: .sample)
        }
        return BookShelfEntry(date: .now, configuration: configuration, state: state ?? .empty, isUnwritten: state == nil)
    }
}

// MARK: - The gallery's books

extension BookShelfWidgetState {
    /// What the widget gallery shows: classics with covers drawn for them
    /// (`GeneratedCover`), the first playing.
    static let sample: BookShelfWidgetState = {
        let hour: TimeInterval = 3600
        let books = [
            Book(id: "sample|1", title: "Pride and Prejudice", author: "Jane Austen", fraction: 0.42, remaining: 6.8 * hour, duration: 11.8 * hour, isFinished: false, isDownloaded: true, cover: nil),
            Book(id: "sample|2", title: "Moby-Dick", author: "Herman Melville", fraction: 0.18, remaining: 19.3 * hour, duration: 23.6 * hour, isFinished: false, isDownloaded: false, cover: nil),
            Book(id: "sample|3", title: "Frankenstein", author: "Mary Shelley", fraction: 0.71, remaining: 2.5 * hour, duration: 8.6 * hour, isFinished: false, isDownloaded: true, cover: nil),
            Book(id: "sample|4", title: "The Odyssey", author: "Homer", fraction: 0.05, remaining: 11.2 * hour, duration: 11.8 * hour, isFinished: false, isDownloaded: false, cover: nil),
            Book(id: "sample|5", title: "Middlemarch", author: "George Eliot", fraction: 0.33, remaining: 23.6 * hour, duration: 35.3 * hour, isFinished: false, isDownloaded: false, cover: nil),
            Book(id: "sample|6", title: "Dracula", author: "Bram Stoker", fraction: 0.56, remaining: 6.8 * hour, duration: 15.5 * hour, isFinished: false, isDownloaded: true, cover: nil),
            Book(id: "sample|7", title: "Jane Eyre", author: "Charlotte Brontë", fraction: 0.12, remaining: 16.6 * hour, duration: 18.9 * hour, isFinished: false, isDownloaded: false, cover: nil),
            Book(id: "sample|8", title: "Treasure Island", author: "Robert Louis Stevenson", fraction: 0.88, remaining: 0.9 * hour, duration: 7.2 * hour, isFinished: false, isDownloaded: false, cover: nil),
            Book(id: "sample|9", title: "Little Women", author: "Louisa May Alcott", fraction: 0.24, remaining: 14.7 * hour, duration: 19.4 * hour, isFinished: false, isDownloaded: false, cover: nil),
            Book(id: "sample|10", title: "Walden", author: "Henry David Thoreau", fraction: 0.61, remaining: 4.5 * hour, duration: 11.6 * hour, isFinished: false, isDownloaded: false, cover: nil),
            Book(id: "sample|11", title: "The Time Machine", author: "H. G. Wells", fraction: 0.09, remaining: 3.2 * hour, duration: 3.5 * hour, isFinished: false, isDownloaded: false, cover: nil),
            Book(id: "sample|12", title: "Great Expectations", author: "Charles Dickens", fraction: 0.47, remaining: 9.6 * hour, duration: 18.2 * hour, isFinished: false, isDownloaded: false, cover: nil),
        ]
        let finished = books.prefix(5).map { book in
            var book = book
            book.fraction = 1
            book.remaining = nil
            book.isFinished = true
            return book
        }
        return BookShelfWidgetState(
            shelves: [
                Shelf.continueListening.rawValue: books,
                Shelf.recentlyAdded.rawValue: Array(books.reversed()),
                Shelf.downloaded.rawValue: books.filter(\.isDownloaded),
                Shelf.finished.rawValue: Array(finished),
            ],
            loadedID: books[0].id,
            isPlaying: true,
            chapter: "Chapter 34",
            needsServer: false
        )
    }()
}
