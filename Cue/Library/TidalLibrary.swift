import SonosKit

/// The signed-in TIDAL account's collection — the songs, albums, artists
/// and playlists saved in TIDAL's My Collection — as the library's lists
/// want it: by offset, where TIDAL pages by cursor. Each page leaves the
/// cursor for the page after it under the offset it ends at, so the lists
/// page through in order; an offset with no cursor is past the end.
@MainActor
final class TidalLibrary {
    static let shared = TidalLibrary()

    enum Kind: String {
        case songs, albums, artists, playlists

        var title: String {
            switch self {
            case .songs: "Songs"
            case .albums: "Albums"
            case .artists: "Artists"
            case .playlists: "Playlists"
            }
        }

        var systemImage: String {
            switch self {
            case .songs: "music.note"
            case .albums: "square.stack"
            case .artists: "music.mic"
            case .playlists: "music.note.list"
            }
        }

        /// The list's screen, newest addition first, as TIDAL keeps it.
        var destination: RouterDestination {
            .playableList(
                title: title,
                // Off, as on the other paged libraries: the index would only
                // reach the pages already loaded.
                showSectionIndex: false,
                allowsGrid: self == .albums || self == .playlists,
                action: { offset in await TidalLibrary.shared.page(self, offset: offset) }
            )
        }
    }

    private var cursors: [String: String] = [:]

    private init() {}

    /// The page of `list` that starts at `offset`.
    func page(_ list: Kind, offset: Int) async -> [PlayableContent] {
        let key = { (offset: Int) in "\(list.rawValue)#\(offset)" }
        let cursor: String?
        if offset == 0 {
            cursor = nil
        } else if let next = cursors[key(offset)] {
            cursor = next
        } else {
            return []
        }
        let service = MusicSearchService.shared
        let page: ([PlayableContent], String?)
        switch list {
        case .songs: page = await service.tidalCollectionTracks(cursor: cursor)
        case .albums: page = await service.tidalCollectionAlbums(cursor: cursor)
        case .artists: page = await service.tidalCollectionArtists(cursor: cursor)
        case .playlists: page = await service.tidalCollectionPlaylists(cursor: cursor)
        }
        let (items, next) = page
        if let next, !items.isEmpty {
            cursors[key(offset + items.count)] = next
        }
        return items
    }
}
