import Foundation

/// How a list of the person's Apple Music library is ordered.
///
/// All of the albums or songs are ordered by MusicKit's index of the
/// library (`MusicLibraryRequest`), so each page arrives in the order and
/// every order can be flipped; a song's release date is the one MusicKit
/// can't sort songs on, so that order is made from the whole list. The
/// favorites, read whole from the web API, are put in order by Cue.
public enum AppleLibrarySort: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case album
    case releaseDate
    case dateAdded

    public var id: String { rawValue }

    /// What each list has to sort on: an artist only its name, a library
    /// song no date added.
    public static func options(for resource: AppleLibraryResource) -> [AppleLibrarySort] {
        switch resource {
        case .albums: [.title, .artist, .releaseDate, .dateAdded]
        case .artists: [.title]
        case .songs: [.title, .artist, .album, .releaseDate]
        case .playlists: [.title, .dateAdded]
        }
    }

    public func label(for resource: AppleLibraryResource) -> String {
        switch self {
        case .title: resource == .artists ? "Name" : "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .releaseDate: "Release Date"
        case .dateAdded: "Date Added"
        }
    }

    public var isDate: Bool {
        self == .releaseDate || self == .dateAdded
    }

    public var ascendingLabel: String {
        isDate ? "Oldest First" : "A – Z"
    }

    public var descendingLabel: String {
        isDate ? "Newest First" : "Z – A"
    }

    /// Whether the order reads best newest first when first chosen.
    public var prefersDescending: Bool {
        isDate
    }
}
