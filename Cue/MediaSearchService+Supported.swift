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
    /// (`ServiceChoiceRow`). Short enough to fit on one line on an iPhone,
    /// so the rows are all one height.
    var choiceDetail: String {
        switch self {
        case .apple: "Your library and the catalog."
        case .plex: "Music and audiobooks you host."
        case .tuneIn: "Live radio. No account needed."
        case .subsonic: "Navidrome, Airsonic and others."
        case .audiobookshelf: "Audiobooks you host."
        case .files: "Audio files, here or in iCloud."
        default: title
        }
    }
}
