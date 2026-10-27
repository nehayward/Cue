import Foundation
import SonosKit

/// A series and its books, in their order in it, for the Audiobooks tab's
/// Series shelf.
struct AudiobookSeries: Identifiable, Codable {
    /// The server and its name for the series.
    let id: String
    let name: String
    let books: [PlayableContent]
}

/// A collection made on the server and its books, in the order they were
/// put in it, for the Audiobooks tab's Collections shelf.
struct AudiobookCollection: Identifiable, Codable {
    /// The server and its id for the collection.
    let id: String
    let name: String
    let books: [PlayableContent]
}

extension AudiobookCollection {
    /// Its books as a list, in its order, each with what's left of it.
    @MainActor
    var destination: RouterDestination {
        let books = books
        return .playableList(
            title: name,
            showSectionIndex: false,
            allowsGrid: true,
            action: { offset in
                guard offset == 0 else { return [] }
                return books.map { $0.withAudiobookProgress(AudiobookProgressStore.shared.progress(for: $0)) }
            }
        )
    }
}
