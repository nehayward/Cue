import Defaults
import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// Someone who writes books: their name, and their Plex artist (a book's
/// album artist, whose picture is theirs) when there is one.
struct AudiobookAuthor: Hashable {
    let name: String
    var plexArtistID: String?

    /// The author of what an artist page was opened for, when it's a book
    /// or one of a book's files (the player's artist line on a book): their
    /// page is their books, not an artist's popular songs, which for an
    /// author are a book's files. Nil for anything else.
    @MainActor
    init?(for content: PlayableContent) {
        // An artist found in a library kept for books (search) is an author.
        if content.content.type == .artist, content.content.service == .plex,
           let section = content.metadata?.librarySectionID,
           PlexAPI.shared.knownAudiobookLibraryKeys.contains(section) {
            let name = content.title.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            self.name = name
            plexArtistID = content.plexRatingKey
            return
        }
        guard let book = AudiobookPlayer.shared.book(containing: content) else { return nil }
        var name = (book.metadata?.artist ?? book.subtitle).trimmingCharacters(in: .whitespaces)
        // Audiobookshelf joins a book's authors with commas ("Terry
        // Pratchett, Neil Gaiman"), a name no author goes by: the page is
        // the first's. A Plex album artist can hold a comma of its own
        // ("Tolkien, J. R. R."), so it's left whole.
        if book.content.service == .audiobookshelf, let first = name.split(separator: ",").first {
            name = first.trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty else { return nil }
        self.name = name
        plexArtistID = book.content.service == .plex ? book.metadata?.artistID : nil
    }

    /// Whether `book` is theirs: their Plex artist's, or by their name —
    /// the whole author line, or any one of the authors of a book with
    /// several, listed with commas. The whole line first: a name can hold
    /// a comma itself ("Tolkien, J. R. R.").
    func wrote(_ book: PlayableContent) -> Bool {
        if let plexArtistID, book.content.service == .plex, book.metadata?.artistID == plexArtistID {
            return true
        }
        let line = book.metadata?.artist ?? book.subtitle
        let isName = { (text: Substring) in
            text.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        return isName(line[...]) || line.split(separator: ",").contains(where: isName)
    }
}
