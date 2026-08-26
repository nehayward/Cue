import MusicSearchKit
import SonosKit
import SwiftUI

struct FavoriteMenuButton: View {
    let item: PlayableContent

    @Environment(PlexRatingCache.self) private var plexRatingCache
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
                    switch contentType {
                    case .album, .libraryAlbum:
                        try? await AppleMusicAPI.shared.updateAlbumFavoriteStatus(albumId: contentID, favorite: newFavorite)
                    default:
                        try? await AppleMusicAPI.shared.updateFavoriteStatus(songId: contentID, favorite: newFavorite)
                    }
                case .plex:
                    let rating = newFavorite ? 10.0 : 0.0
                    plexRatingCache.set(rating, for: contentID)
                    await MusicSearchService.shared.ratePlexTrack(trackID: contentID, rating: Int(rating))
                case .subsonic:
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
                switch contentType {
                case .album, .libraryAlbum:
                    isFavorite = (try? await AppleMusicAPI.shared.isAlbumFavorite(albumId: contentID)) ?? false
                default:
                    isFavorite = (try? await AppleMusicAPI.shared.isFavorite(songId: contentID)) ?? false
                }
            case .plex:
                if let cached = plexRatingCache.ratings[contentID] {
                    isFavorite = cached > 0
                } else if let existing = item.metadata?.userRating {
                    plexRatingCache.set(existing, for: contentID)
                    isFavorite = existing > 0
                } else {
                    let fetched = await MusicSearchService.shared.getPlexTrackRating(trackID: contentID) ?? 0
                    plexRatingCache.set(fetched, for: contentID)
                    isFavorite = fetched > 0
                }
            case .subsonic:
                if contentType.isTrack {
                    isFavorite = await MusicSearchService.shared.isSubsonicTrackLiked(id: contentID)
                } else if let starred = item.metadata?.userRating {
                    isFavorite = starred > 0
                }
            default:
                break
            }
        }
    }
}
