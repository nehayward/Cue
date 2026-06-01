import MusicSearchKit
import SonosKit
import SwiftUI

struct FavoriteMenuButton: View {
    let item: PlayableContent

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
                case .apple:
                    switch contentType {
                    case .album, .libraryAlbum:
                        try? await AppleMusicAPI.shared.updateAlbumFavoriteStatus(albumId: contentID, favorite: newFavorite)
                    default:
                        try? await AppleMusicAPI.shared.updateFavoriteStatus(songId: contentID, favorite: newFavorite)
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
            case .apple:
                switch contentType {
                case .album, .libraryAlbum:
                    isFavorite = (try? await AppleMusicAPI.shared.isAlbumFavorite(albumId: contentID)) ?? false
                default:
                    isFavorite = (try? await AppleMusicAPI.shared.isFavorite(songId: contentID)) ?? false
                }
            default:
                break
            }
        }
    }

}
