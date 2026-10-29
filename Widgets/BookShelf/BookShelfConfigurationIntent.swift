import AppIntents
import Defaults
import WidgetKit

/// What a book shelf widget shows and does, chosen in its Edit Widget sheet.
struct BookShelfConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Book Shelf"
    static let description = IntentDescription("Shows a shelf of your audiobooks.")

    @Parameter(title: "Shelf", default: .continueListening)
    var shelf: BookShelfOption

    @Parameter(title: "Action", default: .playBook)
    var action: BookWidgetAction

    @Parameter(title: "Play in Background", description: "Plays without opening Cue.", default: true)
    var playsInBackground: Bool

    @Parameter(title: "Look", default: .bookshelf)
    var look: BookShelfLook

    @Parameter(title: "Show Progress", default: true)
    var showsProgress: Bool

    /// Play in Background only for Play Book; Look only where there are
    /// shelves to draw, not the one cover of a small widget or the Lock
    /// Screen's.
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .oneOf, [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]) {
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

/// The Audiobooks tab's shelves a widget can show.
enum BookShelfOption: String, AppEnum, CaseIterable {
    case continueListening
    case recentlyAdded
    case downloaded
    case finished

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shelf"
    static let caseDisplayRepresentations: [BookShelfOption: DisplayRepresentation] = [
        .continueListening: "Continue Listening",
        .recentlyAdded: "Recently Added",
        .downloaded: "Downloaded",
        .finished: "Finished",
    ]

    var shelf: BookShelfWidgetState.Shelf {
        switch self {
        case .continueListening: .continueListening
        case .recentlyAdded: .recentlyAdded
        case .downloaded: .downloaded
        case .finished: .finished
        }
    }

    var title: String {
        switch self {
        case .continueListening: "Continue Listening"
        case .recentlyAdded: "Recently Added"
        case .downloaded: "Downloaded"
        case .finished: "Finished"
        }
    }

    /// The mark beside its name.
    var symbol: String {
        switch self {
        case .continueListening: "headphones"
        case .recentlyAdded: "sparkles"
        case .downloaded: "arrow.down.circle"
        case .finished: "checkmark.circle"
        }
    }

    /// What an empty shelf says.
    var emptyMessage: String {
        switch self {
        case .continueListening: "The books you're listening to wait here."
        case .recentlyAdded: "The newest books on your servers show up here."
        case .downloaded: "Books you download show up here."
        case .finished: "Books you finish show up here."
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
    /// Sleeves on a dark shelf, each with its record slid out.
    case records

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Look"
    static let caseDisplayRepresentations: [BookShelfLook: DisplayRepresentation] = [
        .bookshelf: "Bookshelf",
        .records: "Record Shelf",
    ]
}
