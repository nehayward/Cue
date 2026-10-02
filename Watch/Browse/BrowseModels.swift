import Foundation
import WatchSync

/// The lists a server offers, as on the iPhone's library screens.
enum WatchBrowseSection: String, CaseIterable, Hashable {
    case playlists, recentlyAdded, albums, artists, songs

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .recentlyAdded: "Recently Added"
        case .albums: "Albums"
        case .artists: "Artists"
        case .songs: "Songs"
        }
    }

    var symbol: String {
        switch self {
        case .playlists: "music.note.list"
        case .recentlyAdded: "clock"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .songs: "music.note"
        }
    }
}

/// Where in a server's library a page comes from. The server's lists and
/// its search are on the home screen.
enum WatchBrowsePath: Hashable {
    case section(WatchSource, WatchBrowseSection)
    /// An artist's albums.
    case artist(WatchPick)
    case search(WatchSource, String)
}

/// A row: an artist to open on its albums, an album or playlist to open on
/// its songs, or a song to put on the watch with a tap.
struct WatchBrowseItem: Hashable, Identifiable {
    let id: String
    var title: String
    var subtitle: String = ""
    var artworkURL: URL?
    var destination: WatchBrowsePath?
    /// What it puts on the watch, if it goes whole.
    var pick: WatchPick?
    /// The song itself, for a song row: added with a tap, nothing to look up.
    var song: WatchSong?
}

struct WatchBrowsePage {
    /// Rows asked for at a time, whatever the server pages by.
    static let pageSize = 40

    var title: String
    var items: [WatchBrowseItem]
    /// The offset to ask for next, or nil at the end.
    var nextOffset: Int?
    /// What the page is of, when that goes whole (a Subsonic artist).
    var container: WatchBrowseItem?
    /// Said when there's nothing to list.
    var message: String?
}

/// Where a browse row goes: another page, or an album, playlist or artist's
/// songs.
enum BrowseRoute: Hashable {
    case path(WatchBrowsePath)
    case item(WatchBrowseItem)
}
