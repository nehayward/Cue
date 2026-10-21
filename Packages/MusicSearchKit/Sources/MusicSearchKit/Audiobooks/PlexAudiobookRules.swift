import Foundation

/// How Cue tells audiobooks from music on a Plex server.
///
/// Plex has no library type for books. The usual setup is a Music library
/// kept for them, with a book as an album and its author as the album
/// artist (often filled in by the Audnexus agent). Some people keep a few
/// books in their music library instead, tagged with an audiobook genre.
/// Cue takes both: the libraries the listener marks as books (suggested
/// from their name or agent), and albums in the music library carrying one
/// of `genres`.
public enum PlexAudiobookRules {
    /// Whether a Music library looks kept for books, from its title or its
    /// metadata agent. Only a suggestion: the listener's own choice in
    /// settings wins.
    public static func looksLikeAudiobooks(title: String, agent: String?) -> Bool {
        if let agent = agent?.lowercased(), agentHints.contains(where: agent.contains) {
            return true
        }
        let title = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return titleHints.contains(where: title.contains)
    }

    /// Agents that only make sense for books.
    static let agentHints = ["audnexus", "audiobook"]

    /// Words in a library's name that mean books, folded to lowercase with
    /// no accents: "Audiobooks", "Books", "Hörbücher", "Livres audio",
    /// "Audiolibros", "Luisterboeken".
    static let titleHints = ["book", "horbuch", "horbucher", "livre", "libro", "boeken", "ljudbok", "lydbok"]

    /// Album genres that mark a book kept among music.
    public static let genres = ["Audiobook", "Audiobooks", "Audio Book", "Audio Books", "Spoken Word", "Hörbuch", "Hörbücher"]

    /// Whether a genre tag is one of `genres`, ignoring case and accents.
    public static func isAudiobookGenre(_ tag: String) -> Bool {
        let folded = fold(tag)
        return foldedGenres.contains(folded)
    }

    private static let foldedGenres = Set(genres.map(fold))

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
