import MusicSearchKit

/// Which of MusicSearchKit's services Cue actually offers. Kept in the app
/// rather than the package: the package keeps every backend it knows how to
/// talk to, and this is Cue's choice of what to show.
extension MediaSearchService {
    /// The services Cue offers, in the order the app lists them. Everything
    /// here plays from this device or from something the user runs
    /// themselves: Apple Music, a Plex or Subsonic server, radio, an
    /// Audiobookshelf server's books, and a folder of files. The streaming services that only work through a
    /// Sonos account (Spotify, Tidal, Deezer, …) keep their cases in the
    /// package so stored settings still decode, but they are never listed
    /// or enabled here.
    static let supported: [MediaSearchService] = [.apple, .plex, .tuneIn, .subsonic, .audiobookshelf, .files]

    /// Whether this is one of the services Cue offers (see `supported`).
    var isSupported: Bool {
        Self.supported.contains(self)
    }

    /// A line on what the service is, under its name where Cue offers it
    /// (`ServiceChoiceRow`).
    var choiceDetail: String {
        switch self {
        case .apple: "Your library, the catalog and Apple Music radio."
        case .plex: "Music and audiobooks from your Plex Media Server."
        case .tuneIn: "Live radio from around the world. No account needed."
        case .subsonic: "Navidrome, Airsonic or any Subsonic server."
        case .audiobookshelf: "Audiobooks from your Audiobookshelf server."
        case .files: "Music and books in a folder, here or in iCloud Drive."
        default: title
        }
    }
}
