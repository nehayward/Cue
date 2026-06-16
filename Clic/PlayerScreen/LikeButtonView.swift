import MusicSearchKit
import SonosKit
import SwiftUI

struct LikeButtonView: View {
    var group: GroupRoom

    @Environment(PlexRatingCache.self) private var plexRatingCache
    @State private var isFavorite = false
    @State private var plexRating: Double = 0
    @State private var favoriteAnimationTrigger = 0

    private var trackID: String { group.coordinatorRoom.track.trackID }

    var body: some View {
        let service = group.coordinatorRoom.track.musicService

        switch service {
        case .plex:
            Button {
                let newRating = plexRating > 0 ? 0.0 : 10.0
                plexRating = newRating
                plexRatingCache.set(newRating, for: trackID)
                HapticManager.shared.fireHaptic(newRating > 0 ? .notification(.success) : .selection)
                if newRating > 0 { favoriteAnimationTrigger += 1 }
                Task { await MusicSearchService.shared.ratePlexTrack(trackID: trackID, rating: Int(newRating)) }
            } label: {
                plexHeartImage
                    .help("Favorite Song")
                    .accessibilityLabel("Favorite Song")
                    .phaseAnimator(
                        [1.0, 1.25, 1.0],
                        trigger: favoriteAnimationTrigger,
                        content: { content, scale in content.scaleEffect(scale) },
                        animation: { _ in .bouncy.delay(0.20) }
                    )
            }
            .task(id: group.coordinatorRoom.track.id) {
                let fetched = await MusicSearchService.shared.getPlexTrackRating(trackID: trackID)
                let rating = fetched ?? 0
                plexRatingCache.set(rating, for: trackID)
                var transaction = Transaction(animation: .none)
                transaction.disablesAnimations = true
                withTransaction(transaction) { plexRating = rating }
            }

        case .spotify, .soundcloud, .apple, .deezer:
            Button {
                let newFavorite = !isFavorite
                isFavorite = newFavorite
                HapticManager.shared.fireHaptic(newFavorite ? .notification(.success) : .selection)
                if newFavorite { favoriteAnimationTrigger += 1 }
                Task { await performAction(service: service, favorite: newFavorite) }
            } label: {
                Image(systemName: service == .apple ? "star" : "heart")
                    .symbolVariant(isFavorite ? .fill : .none)
                    .foregroundStyle(service.brandColor.gradient)
                    .help("Favorite Song")
                    .accessibilityLabel("Favorite Song")
                    .phaseAnimator(
                        [1.0, 1.25, 1.0],
                        trigger: favoriteAnimationTrigger,
                        content: { content, scale in content.scaleEffect(scale) },
                        animation: { _ in .bouncy.delay(0.20) }
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

    @ViewBuilder private var plexHeartImage: some View {
        let color = MusicService.plex.brandColor
        let fill = plexRating / 10.0
        if plexRating == 0 {
            Image(systemName: "heart")
                .foregroundStyle(color.gradient)
        } else {
            Image(systemName: "heart.fill")
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: color, location: 0),
                            .init(color: color, location: fill),
                            .init(color: color.opacity(0.25), location: fill),
                            .init(color: color.opacity(0.25), location: 1),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
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
            if favorite { await MusicSearchService.shared.saveSpotifyTrack(id: trackID) }
            else { await MusicSearchService.shared.deleteSpotifyTrack(id: trackID) }
        case .soundcloud:
            if favorite { await MusicSearchService.shared.likeSoundCloudTrack(id: trackID) }
            else { await MusicSearchService.shared.unlikeSoundCloudTrack(id: trackID) }
        case .deezer:
            if favorite { await MusicSearchService.shared.likeDeezerTrack(id: trackID) }
            else { await MusicSearchService.shared.unlikeDeezerTrack(id: trackID) }
        case .apple:
            try? await AppleMusicAPI.shared.updateFavoriteStatus(songId: trackID, favorite: favorite)
        default:
            break
        }
    }

    private func checkFavorite(service: MusicService) async -> Bool {
        switch service {
        case .spotify: await MusicSearchService.shared.isSpotifyTrackSaved(id: trackID)
        case .soundcloud: await MusicSearchService.shared.isSoundCloudTrackLiked(id: trackID) ?? false
        case .apple: (try? await AppleMusicAPI.shared.isFavorite(songId: trackID)) ?? false
        case .deezer: await MusicSearchService.shared.isDeezerTrackLiked(id: trackID)
        default: false
        }
    }
}
