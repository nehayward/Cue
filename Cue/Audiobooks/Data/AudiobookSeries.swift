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
