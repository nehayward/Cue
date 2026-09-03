import MusicSearchKit
import SwiftUI

/// One of the collections a provider's library is split into — the rows on
/// its browse screen's front page, and the tabs in its sidebar section.
enum ProviderCollection: String, CaseIterable, Hashable, Codable {
    case artists
    case albums
    case songs
    case playlists
    case playlistFolders
    case recentlyPlayed
    case recentlyAdded
    case recommendedAlbums
    case personalStations
    case likedSongs
    case favoriteTracks
    case favoriteAlbums
    case favoriteArtists
    case genres
    case folders
    case importedPlaylists
    case savedPlaylists

    var title: String {
        switch self {
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        case .playlists: "Playlists"
        case .playlistFolders: "Playlist Folders"
        case .recentlyPlayed: "Recently Played"
        case .recentlyAdded: "Recently Added"
        case .recommendedAlbums: "Recommended Albums"
        case .personalStations: "Personal Stations"
        case .likedSongs: "Liked Songs"
        case .favoriteTracks: "Favorite Tracks"
        case .favoriteAlbums: "Favorite Albums"
        case .favoriteArtists: "Favorite Artists"
        case .genres: "Genres"
        case .folders: "Folders"
        case .importedPlaylists: "Imported Playlists"
        case .savedPlaylists: "Saved Playlists"
        }
    }

    var systemImage: String {
        switch self {
        case .artists, .favoriteArtists: "music.mic"
        case .albums, .favoriteAlbums, .recommendedAlbums: "square.stack"
        case .songs, .likedSongs, .favoriteTracks: "music.note"
        case .playlists, .importedPlaylists, .savedPlaylists: "rectangle.stack.badge.play"
        case .playlistFolders, .folders: "folder"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .recentlyAdded: "clock"
        case .personalStations: "dot.radiowaves.left.and.right"
        case .genres: "theatermasks"
        }
    }
}

extension MediaSearchService {
    /// Every collection this provider's library offers, in the order its
    /// browse screen lists them. Empty for a provider that browses some
    /// other way (Pandora and Sonos Radio list stations by section) or has
    /// no browse screen at all. Add a provider here — and an arm to
    /// `ProviderLibrary.destination(for:)` — when it has collections to page.
    var tabCollections: [ProviderCollection] {
        switch self {
        case .apple:
            [.artists, .albums, .songs, .playlists, .playlistFolders, .recentlyPlayed, .recentlyAdded, .recommendedAlbums, .personalStations]
        case .spotify:
            [.likedSongs, .albums, .playlists]
        case .soundcloud:
            [.likedSongs, .playlists]
        case .deezer:
            [.favoriteTracks, .favoriteAlbums, .favoriteArtists, .playlists]
        case .subsonic:
            [.artists, .albums, .songs, .recentlyAdded, .playlists]
        case .library:
            [.artists, .albums, .songs, .genres, .folders, .importedPlaylists, .savedPlaylists]
        case .plex:
            [.artists, .albums, .songs, .playlists]
        case .tidal, .tuneIn, .sonosRadio, .pandora:
            []
        }
    }

    /// The collections switched on when the provider is first added. The
    /// core four where a provider has them, so a section starts at a size
    /// the sidebar can take; the rest wait in Customize Tabs.
    var defaultTabCollections: [ProviderCollection] {
        let core: Set<ProviderCollection> = [
            .artists, .albums, .songs, .playlists,
            .likedSongs, .favoriteTracks, .favoriteAlbums, .favoriteArtists
        ]
        let defaults = tabCollections.filter { core.contains($0) }
        return defaults.isEmpty ? tabCollections : defaults
    }

    /// Whether the user can add this provider to the tab view at all.
    var canBeTab: Bool {
        isBrowseSupported && !tabCollections.isEmpty
    }

    /// The `customizationID` of this provider's own tab. A stable string the
    /// system keeps the user's sidebar edits under.
    var tabCustomizationID: String {
        "cue.tab.\(rawValue)"
    }

    func tabCustomizationID(for collection: ProviderCollection) -> String {
        "cue.tab.\(rawValue).\(collection.rawValue)"
    }
}
