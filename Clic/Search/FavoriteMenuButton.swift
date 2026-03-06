import MusicSearchKit
import SonosKit
import SwiftUI

struct FavoriteMenuButton: View {
    let item: PlayableContent

    @State private var isFavorite = false

    private var service: MusicService { item.content.service }
    private var trackID: String { item.id }

    var body: some View {
        Button {
            let newFavorite = !isFavorite
            isFavorite = newFavorite
            HapticManager.shared.fireHaptic(newFavorite ? .notification(.success) : .selection)
            Task {
                switch service {
                case .spotify:
                    if newFavorite {
                        await MusicSearchService.shared.saveSpotifyTrack(id: trackID)
                    } else {
                        await MusicSearchService.shared.deleteSpotifyTrack(id: trackID)
                    }
                case .soundcloud:
                    if newFavorite {
                        await MusicSearchService.shared.likeSoundCloudTrack(id: trackID)
                    } else {
                        await MusicSearchService.shared.unlikeSoundCloudTrack(id: trackID)
                    }
                case .apple:
                    try? await AppleMusicAPI.shared.updateFavoriteStatus(songId: trackID, favorite: newFavorite)
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
                isFavorite = await MusicSearchService.shared.isSpotifyTrackSaved(id: trackID)
            case .soundcloud:
                isFavorite = await MusicSearchService.shared.isSoundCloudTrackLiked(id: trackID) ?? false
            case .apple:
                isFavorite = (try? await AppleMusicAPI.shared.isFavorite(songId: trackID)) ?? false
            default:
                break
            }
        }
    }
}
