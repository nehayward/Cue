import MusicSearchKit
import OrderedCollections
import SonosKit
import SwiftUI

/// Where a provider's collections come from: the same `RouterDestination`s
/// its browse screen's rows push, built from the same services. A collection
/// tab and the row on the library's front page therefore show one screen,
/// and adding a collection here is adding it to both.
@MainActor
struct ProviderLibrary {
    let service: MediaSearchService
    let musicSearchService: MusicSearchService
    let appleMusicBrowseService: AppleMusicBrowseService
    let spotifyBrowseService: SpotifyBrowseService
    let soundCloudBrowseService: SoundCloudBrowseService
    let deezerBrowseService: DeezerBrowseService
    let subsonicBrowseService: SubsonicBrowseService
    let plexBrowseService: PlexBrowseService
    let libraryBrowseService: LibraryBrowseService
    /// The group the Sonos library's lists are scoped to.
    let group: GroupRoom?

    /// Whether the provider is signed in and set up far enough to browse.
    var isReady: Bool {
        switch service {
        case .plex: musicSearchService.isPlexAuthorized && musicSearchService.plexServerID != nil
        case .deezer: deezerBrowseService.isAuthenticated
        case .subsonic: subsonicBrowseService.isAuthenticated
        case .files: FilesLibraryService.shared.isConfigured
        default: true
        }
    }

    /// What the provider's front page loads when it opens, so a collection
    /// tab that reads the browse service's cache has data waiting too.
    func load() async {
        switch service {
        case .plex:
            await plexBrowseService.updateUserPlaylists()
            // Opening the library is the moment to notice the server has
            // more songs than the synced copy — Songs is one tap away.
            await musicSearchService.refreshPlexLibraryIfChanged()
        case .deezer:
            await deezerBrowseService.load()
        case .subsonic:
            await subsonicBrowseService.load()
        case .soundcloud:
            await soundCloudBrowseService.updateLikedTracks()
            await soundCloudBrowseService.updateLikedPlaylists()
        case .library:
            await libraryBrowseService.refreshLibraryIfChanged()
        case .files:
            await FilesLibraryService.shared.scanIfNeeded()
        default:
            break
        }
    }

    /// The screen a collection opens, or nil for a collection this provider
    /// doesn't have.
    func destination(for collection: ProviderCollection) -> RouterDestination? {
        switch service {
        case .apple: appleDestination(for: collection)
        case .spotify: spotifyDestination(for: collection)
        case .soundcloud: soundCloudDestination(for: collection)
        case .deezer: deezerDestination(for: collection)
        case .subsonic: subsonicDestination(for: collection)
        case .library: libraryDestination(for: collection)
        case .plex: plexDestination(for: collection)
        case .files: Self.filesDestination(for: collection)
        case .tidal, .tuneIn, .sonosRadio, .pandora: nil
        }
    }

    // MARK: - Apple Music

    private func appleDestination(for collection: ProviderCollection) -> RouterDestination? {
        let apple = appleMusicBrowseService
        let items = Bindable(apple)

        switch collection {
        case .artists:
            return .playableLibraryList(title: "Artists", items: items.userArtists, action: { offset in
                await apple.updateUsersAppleArtists(offset: offset)
            })
        case .albums:
            return .playableLibraryList(title: "Albums", items: items.userAlbums, action: { _ in
                await apple.updateUsersAppleAlbums()
            })
        case .songs:
            return .playableLibraryList(title: "Songs", items: items.userSongs, action: { _ in
                await apple.updateUsersAppleSongs()
            })
        case .playlists:
            return .playableGridScreen(title: "Playlists", items: items.userPlaylists, action: { offset in
                await apple.updateUsersApplePlaylists(offset: offset)
            })
        case .playlistFolders:
            return .playableGridScreen(title: "Playlist Folders", items: items.userPlaylistFolders, action: { offset in
                await apple.updateUsersApplePlaylistFolders(offset: offset)
            })
        case .recentlyPlayed:
            return .playableGridScreen(title: "Recently Played", items: items.usersRecents, action: { offset in
                await apple.updateUsersRecentPlayed(offset: offset)
            })
        case .recentlyAdded:
            return .playableGridScreen(title: "Recently Added", items: items.usersRecentsAdded, action: { offset in
                await apple.updateUsersRecentAddedTracks(offset: offset)
            })
        case .recommendedAlbums:
            return .playableGridScreen(title: "Recommended Albums", items: items.recommendedAlbums, action: { offset in
                await apple.updateRecommendedAlbums(offset: offset)
            })
        case .personalStations:
            return .playableGridScreen(title: "Personal Stations", items: items.userStations, action: { offset in
                await apple.updateRadioStations(offset: offset)
            })
        default:
            return nil
        }
    }

    // MARK: - Spotify

    private func spotifyDestination(for collection: ProviderCollection) -> RouterDestination? {
        let spotify = spotifyBrowseService

        switch collection {
        case .likedSongs:
            return .playableList(title: "Songs", playAllItem: .spotifyLikes, showSectionIndex: false, action: { _ in
                await spotify.updateSongs()
                return Array(spotify.tracks)
            })
        case .albums:
            return .playableList(title: "Spotify Albums", showSectionIndex: false, action: { offset in
                await spotify.userAlbums(offset: offset, limit: 25)
                return Array(spotify.albums)
            })
        case .playlists:
            return .playableList(title: "Spotify Playlists", showSectionIndex: false, action: { offset in
                await spotify.updatePlaylists(offset: offset)
                return Array(spotify.playlists)
            })
        default:
            return nil
        }
    }

    // MARK: - SoundCloud

    private func soundCloudDestination(for collection: ProviderCollection) -> RouterDestination? {
        let soundCloud = soundCloudBrowseService

        switch collection {
        case .likedSongs:
            return .playableList(title: "SoundCloud Liked Tracks", playAllItem: .soundCloudLikes, showSectionIndex: false, action: { offset in
                if offset >= soundCloud.likedTracks.count && soundCloud.canLoadMore {
                    await soundCloud.loadMoreTracks()
                }
                return Array(soundCloud.likedTracks.prefix(offset + 50))
            })
        case .playlists:
            return .playableList(title: "SoundCloud Playlists", showSectionIndex: false, action: { offset in
                if offset >= soundCloud.likedPlaylists.count && soundCloud.canLoadMorePlaylists {
                    await soundCloud.loadMorePlaylists()
                }
                return Array(soundCloud.likedPlaylists.prefix(offset + 50))
            })
        default:
            return nil
        }
    }

    // MARK: - Deezer

    private func deezerDestination(for collection: ProviderCollection) -> RouterDestination? {
        let musicSearchService = musicSearchService

        switch collection {
        case .favoriteTracks:
            return .playableList(title: "Favorite Tracks", showSectionIndex: false, action: { offset in
                await musicSearchService.deezerUserFavoriteTracks(offset: offset)
            })
        case .favoriteAlbums:
            return .playableList(title: "Favorite Albums", showSectionIndex: false, action: { offset in
                await musicSearchService.deezerUserFavoriteAlbums(offset: offset)
            })
        case .favoriteArtists:
            return .playableList(title: "Favorite Artists", showSectionIndex: false, action: { offset in
                await musicSearchService.deezerUserFavoriteArtists(offset: offset)
            })
        case .playlists:
            return .playableGridScreen(title: "Playlists", items: Bindable(deezerBrowseService).userPlaylists, action: { _ in })
        default:
            return nil
        }
    }

    // MARK: - Subsonic

    private func subsonicDestination(for collection: ProviderCollection) -> RouterDestination? {
        let musicSearchService = musicSearchService

        switch collection {
        case .artists:
            return .playableList(
                title: "Artists",
                // Off for now: the index fights the paginated loads
                // (scrolling to a letter jumps past unloaded pages).
                showSectionIndex: false,
                action: { offset in await musicSearchService.subsonicArtists(offset: offset) }
            )
        case .albums:
            return .playableList(
                title: "Albums",
                showSectionIndex: false,
                // Each option carries its own loader, so the list needs
                // no separate default action.
                sortOptions: SubsonicLibraryLists.albumSortOptions(musicSearchService: musicSearchService),
                sortKey: SubsonicLibraryLists.albumSortKey,
                searchAction: { query, offset in
                    await musicSearchService.searchSubsonicAlbums(query: query, offset: offset)
                }
            )
        case .songs:
            return .playableList(
                title: "Songs",
                showSectionIndex: false,
                sortOptions: SubsonicLibraryLists.songSortOptions(musicSearchService: musicSearchService),
                sortKey: SubsonicLibraryLists.songSortKey,
                refreshAction: { musicSearchService.clearSubsonicSongCache() },
                searchAction: { query, offset in
                    await musicSearchService.searchSubsonicSongs(query: query, offset: offset)
                },
                loadingStatus: SubsonicLibraryLists.songSyncStatus(musicSearchService: musicSearchService)
            )
        case .recentlyAdded:
            return .playableList(title: "Recently Added", showSectionIndex: false, action: { offset in
                await musicSearchService.subsonicRecentAlbums(offset: offset)
            })
        case .playlists:
            return .playableGridScreen(title: "Playlists", items: Bindable(subsonicBrowseService).userPlaylists, action: { _ in })
        default:
            return nil
        }
    }

    // MARK: - Sonos music library

    private func libraryDestination(for collection: ProviderCollection) -> RouterDestination? {
        let library = libraryBrowseService
        let items = Bindable(library)

        switch collection {
        case .artists:
            return .playableContentList(group: group, contentType: .artist)
        case .albums:
            return .playableContentList(group: group, contentType: .album)
        case .songs:
            return .playableList(
                title: "Songs",
                // Off for now, as on the other libraries: the index and
                // the row count fight each other on a list this long.
                showSectionIndex: false,
                refreshAction: { library.clearSongCache() },
                searchAction: { query, offset in
                    await library.searchSongs(query: query, offset: offset)
                },
                loadingStatus: LocalLibraryLists.songSyncStatus(browseService: library),
                action: { offset in await library.allSongs(offset: offset) }
            )
        case .genres:
            return .genreList
        case .folders:
            return .playableLibraryList(title: "Folders", items: items.folders, action: { offset in
                await library.updateFolders(offset: offset)
            })
        case .importedPlaylists:
            return .playableLibraryList(title: "Imported Playlists", items: items.importedPlaylists, action: { offset in
                await library.updateImportedPlaylists(offset: offset)
            })
        case .savedPlaylists:
            return .playableContentList(group: group, contentType: .playlist)
        default:
            return nil
        }
    }

    // MARK: - Files

    /// The folder's index is in memory, so every list answers in one page
    /// and search filters the index itself. Static, and public to the app:
    /// the Files browse screen's rows push the same destinations.
    static func filesDestination(for collection: ProviderCollection) -> RouterDestination? {
        let files = FilesLibraryService.shared

        switch collection {
        case .artists:
            return .playableList(title: "Artists", refreshAction: { await files.scan() }, action: { offset in
                await files.scanIfNeeded()
                return offset == 0 ? files.artists : []
            })
        case .albums:
            return .playableList(title: "Albums", showSectionIndex: false, refreshAction: { await files.scan() }, action: { offset in
                await files.scanIfNeeded()
                return offset == 0 ? files.albums : []
            })
        case .songs:
            return .playableList(
                title: "Songs",
                showSectionIndex: false,
                refreshAction: { await files.scan() },
                searchAction: { query, offset in
                    offset == 0 ? files.search(query: query).filter { $0.content.type == .track } : []
                },
                loadingStatus: {
                    if files.isScanning {
                        return files.foundCount > 0 ? "\(files.scannedCount) of \(files.foundCount)" : "Scanning…"
                    }
                    let count = files.songs.count
                    return count == 0 ? nil : (count == 1 ? "1 song" : "\(count.formatted()) songs")
                },
                action: { offset in
                    await files.scanIfNeeded()
                    return files.songs(offset: offset)
                }
            )
        default:
            return nil
        }
    }

    // MARK: - Plex

    private func plexDestination(for collection: ProviderCollection) -> RouterDestination? {
        let plex = plexBrowseService
        let musicSearchService = musicSearchService

        switch collection {
        case .artists:
            return .playableList(title: "Artists", action: { offset in
                await plex.artists(offset: offset)
            })
        case .albums:
            return .playableList(title: "Albums", action: { offset in
                await plex.updateUserAlbums(offset: offset)
            })
        case .songs:
            return .playableList(
                title: "Songs",
                // Off for now, as on Subsonic: the index re-buckets the
                // list A–Z by title, which silently undoes every sort but
                // Title.
                showSectionIndex: false,
                sortOptions: PlexLibraryLists.songSortOptions(musicSearchService: musicSearchService),
                sortKey: PlexLibraryLists.songSortKey,
                refreshAction: { musicSearchService.clearPlexSongCache() },
                searchAction: { query, offset in
                    await musicSearchService.searchPlexSongs(query: query, offset: offset)
                },
                loadingStatus: PlexLibraryLists.songSyncStatus(musicSearchService: musicSearchService)
            )
        case .playlists:
            return .playableGridScreen(title: "Playlists", items: Bindable(plex).userPlaylists, action: { offset in
                await plex.updateUserPlaylists(offset: offset)
            })
        default:
            return nil
        }
    }
}
