import MusicSearchKit
import SonosKit
import SwiftUI

struct FavoriteMenuButton: View {
    let item: PlayableContent

    @Environment(FavoriteRatingCache.self) private var favoriteRatingCache
    @State private var isFavorite = false

    private var service: MusicService { item.content.service }
    private var contentID: String { item.id }
    private var contentType: ContentType { item.content.type }

    var body: some View {
        Button {
            let newFavorite = !isFavorite
            isFavorite = newFavorite
            HapticManager.shared.fireHaptic(newFavorite ? .notification(.success) : .selection)
            Task {
                switch service {
                case .spotify:
                    switch contentType {
                    case .album, .libraryAlbum:
                        if newFavorite {
                            await MusicSearchService.shared.saveSpotifyAlbum(id: contentID)
                        } else {
                            await MusicSearchService.shared.deleteSpotifyAlbum(id: contentID)
                        }
                    default:
                        if newFavorite {
                            await MusicSearchService.shared.saveSpotifyTrack(id: contentID)
                        } else {
                            await MusicSearchService.shared.deleteSpotifyTrack(id: contentID)
                        }
                    }
                case .soundcloud:
                    if newFavorite {
                        await MusicSearchService.shared.likeSoundCloudTrack(id: contentID)
                    } else {
                        await MusicSearchService.shared.unlikeSoundCloudTrack(id: contentID)
                    }
                case .deezer:
                    if newFavorite {
                        await MusicSearchService.shared.likeDeezerTrack(id: contentID)
                    } else {
                        await MusicSearchService.shared.unlikeDeezerTrack(id: contentID)
                    }
                case .apple:
                    // As Plex's: the row's star and the favorites lists
                    // follow the tap, not the next read.
                    favoriteRatingCache.set(newFavorite ? 1 : 0, for: contentID)
                    // A row from MusicKit has the device's id, which Apple's
                    // ratings don't know: the web's for the same item.
                    let browse = AppleMusicBrowseService.shared
                    let id = await browse.webLibraryID(for: item) ?? contentID
                    switch contentType {
                    case .album, .libraryAlbum:
                        try? await AppleMusicAPI.shared.updateAlbumFavoriteStatus(albumId: id, favorite: newFavorite)
                    default:
                        try? await AppleMusicAPI.shared.updateFavoriteStatus(songId: id, favorite: newFavorite)
                    }
                    browse.favoritesChanged()
                case .plex:
                    let rating = newFavorite ? 10.0 : 0.0
                    favoriteRatingCache.set(rating, for: contentID)
                    await MusicSearchService.shared.ratePlexTrack(trackID: contentID, rating: Int(rating))
                case .subsonic:
                    // Same session-local echo as Plex, so the row's heart
                    // flips on tap instead of on the next library sync.
                    favoriteRatingCache.set(newFavorite ? 1 : 0, for: contentID)
                    // star/unstar works for songs, albums and artists alike.
                    if newFavorite {
                        await MusicSearchService.shared.likeSubsonicTrack(id: contentID)
                    } else {
                        await MusicSearchService.shared.unlikeSubsonicTrack(id: contentID)
                    }
                default:
                    break
                }
            }
        } label: {
            Label(
                "Favorite",
                systemImage: isFavorite
                    ? (service == .apple ? "star.fill" : "heart.fill")
                    : (service == .apple ? "star" : "heart")
            )
            .tint(service.brandColor)
        }
        .task {
            switch service {
            case .spotify:
                switch contentType {
                case .album, .libraryAlbum:
                    isFavorite = await MusicSearchService.shared.isSpotifyAlbumSaved(id: contentID)
                default:
                    isFavorite = await MusicSearchService.shared.isSpotifyTrackSaved(id: contentID)
                }
            case .soundcloud:
                isFavorite = await MusicSearchService.shared.isSoundCloudTrackLiked(id: contentID) ?? false
            case .deezer:
                isFavorite = await MusicSearchService.shared.isDeezerTrackLiked(id: contentID)
            case .apple:
                // Library items carry it (`inFavorites`, or matched to the
                // favorites for MusicKit's rows); others ask.
                if let known = favoriteRatingCache.ratings[contentID] ?? item.metadata?.userRating {
                    isFavorite = known > 0
                    return
                }
                switch contentType {
                case .album, .libraryAlbum:
                    isFavorite = (try? await AppleMusicAPI.shared.isAlbumFavorite(albumId: contentID)) ?? false
                default:
                    isFavorite = (try? await AppleMusicAPI.shared.isFavorite(songId: contentID)) ?? false
                }
            case .plex:
                if let cached = favoriteRatingCache.ratings[contentID] {
                    isFavorite = cached > 0
                } else if let existing = item.metadata?.userRating {
                    favoriteRatingCache.set(existing, for: contentID)
                    isFavorite = existing > 0
                } else {
                    let fetched = await MusicSearchService.shared.getPlexTrackRating(trackID: contentID) ?? 0
                    favoriteRatingCache.set(fetched, for: contentID)
                    isFavorite = fetched > 0
                }
            case .subsonic:
                // The mapping carries starred state as userRating; only rows
                // without it (Sonos queue items) need the network read.
                if let starred = item.metadata?.userRating {
                    isFavorite = starred > 0
                } else if contentType.isTrack {
                    isFavorite = await MusicSearchService.shared.isSubsonicTrackLiked(id: contentID)
                }
            default:
                break
            }
        }
    }
}
