import Foundation

/// How the user's Apple Music library albums are ordered. Each case is a
/// property `MusicLibraryRequest<Album>` can sort on, so the order comes
/// from MusicKit's own index of the library and holds across every page.
public enum AppleLibraryAlbumSort: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case recentlyAdded

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .recentlyAdded: "Recently Added"
        }
    }

    public var ascendingLabel: String {
        switch self {
        case .title, .artist: "A – Z"
        case .recentlyAdded: "Oldest First"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title, .artist: "Z – A"
        case .recentlyAdded: "Newest First"
        }
    }

    /// Whether the order reads best newest-first when first chosen.
    public var prefersDescending: Bool {
        self == .recentlyAdded
    }
}
