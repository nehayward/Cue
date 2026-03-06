import MusicSearchKit
import SonosKit
import SwiftUI

struct LikeButtonView: View {
    var group: GroupRoom

    @State private var isFavorite = false
    @State private var favoriteAnimationTrigger = 0

    private var trackID: String { group.coordinatorRoom.track.trackID }

    var body: some View {
        let service = group.coordinatorRoom.track.musicService

        switch service {
        case .spotify, .soundcloud, .apple:
            Button {
                let newFavorite = !isFavorite
                isFavorite = newFavorite
                HapticManager.shared.fireHaptic(newFavorite ? .notification(.success) : .selection)
                if newFavorite { favoriteAnimationTrigger += 1 }
                Task { await performAction(service: service, favorite: newFavorite) }
            } label: {
                Image(systemName: service == .apple ? "star" : "heart")
                    .symbolVariant(isFavorite ? .fill : .none)
                    .foregroundStyle(foregroundStyle(for: service))
                    .help("Favorite Song")
                    .accessibilityLabel("Favorite Song")
                    .phaseAnimator(
                        [1.0, 1.25, 1.0],
                        trigger: favoriteAnimationTrigger,
                        content: { content, scale in
                            content.scaleEffect(scale)
                        },
                        animation: { _ in
                            .bouncy.delay(0.20)
                        }
                    )
            }
            .task(id: group.coordinatorRoom.track.id) {
                let result = await checkFavorite(service: service)
                var transaction = Transaction(animation: .none)
                transaction.disablesAnimations = true
                withTransaction(transaction) { isFavorite = result }
            }

        default:
            EmptyView()
        }
    }

    private func foregroundStyle(for service: MusicService) -> AnyShapeStyle {
        switch service {
        case .spotify: AnyShapeStyle(MusicService.spotify.brandColor.gradient)
        case .soundcloud: AnyShapeStyle(MusicService.soundcloud.brandColor.gradient)
        case .apple: AnyShapeStyle(.red.gradient)
        default: AnyShapeStyle(.red.gradient)
        }
    }

    private func performAction(service: MusicService, favorite: Bool) async {
        switch service {
        case .spotify:
            if favorite {
                await MusicSearchService.shared.saveSpotifyTrack(id: trackID)
            } else {
                await MusicSearchService.shared.deleteSpotifyTrack(id: trackID)
            }
        case .soundcloud:
            if favorite {
                await MusicSearchService.shared.likeSoundCloudTrack(id: trackID)
            } else {
                await MusicSearchService.shared.unlikeSoundCloudTrack(id: trackID)
            }
        case .apple:
            try? await AppleMusicAPI.shared.updateFavoriteStatus(songId: trackID, favorite: favorite)
        default:
            break
        }
    }

    private func checkFavorite(service: MusicService) async -> Bool {
        switch service {
        case .spotify:
            await MusicSearchService.shared.isSpotifyTrackSaved(id: trackID)
        case .soundcloud:
            await MusicSearchService.shared.isSoundCloudTrackLiked(id: trackID) ?? false
        case .apple:
            (try? await AppleMusicAPI.shared.isFavorite(songId: trackID)) ?? false
        default:
            false
        }
    }
}
