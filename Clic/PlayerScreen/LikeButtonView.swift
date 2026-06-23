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
                Label {
                    Text("Favorite")
                } icon: {
                    plexHeartImage
                }
                .labelStyle(.iconOnly)
                .symbolEffect(.bounce, value: favoriteAnimationTrigger)
                .help("Favorite Song")
                .accessibilityLabel("Favorite Song")
            }
            .buttonBorderShape(.circle)
            .task(id: group.coordinatorRoom.track.id) {
                let fetched = await MusicSearchService.shared.getPlexTrackRating(trackID: trackID)
                let rating = fetched ?? 0
                plexRatingCache.set(rating, for: trackID)
                var transaction = Transaction(animation: .none)
                transaction.disablesAnimations = true
                withTransaction(transaction) { plexRating = rating }
            }
            .tint(MusicService.plex.brandColor.gradient)

        case .spotify, .soundcloud, .apple, .deezer:
            Button {
                let newFavorite = !isFavorite
                isFavorite = newFavorite
                HapticManager.shared.fireHaptic(newFavorite ? .notification(.success) : .selection)
                if newFavorite { favoriteAnimationTrigger += 1 }
                Task { await performAction(service: service, favorite: newFavorite) }
            } label: {
                Label {
                    Text("Favorite")
                } icon: {
                    Image(systemName: service == .apple ? "star" : "heart")
                        .symbolVariant(isFavorite ? .fill : .none)
                }
                .foregroundStyle(service.brandColor.gradient)
                .labelStyle(.iconOnly)
                .symbolEffect(.bounce, value: favoriteAnimationTrigger)
                .help("Favorite Song")
                .accessibilityLabel("Favorite Song")
            }
            .buttonBorderShape(.circle)
            .task(id: group.coordinatorRoom.track.id) {
                let result = await checkFavorite(service: service)
                var transaction = Transaction(animation: .none)
                transaction.disablesAnimations = true
                withTransaction(transaction) { isFavorite = result }
            }
            .tint(service.brandColor.gradient)

        default:
            EmptyView()
        }
    }

    // Use a single `Image(systemName: "heart")` (toggling `.symbolVariant`) rather than
    // swapping between "heart" and "heart.fill" views, so the symbol keeps a stable identity
    // and `.symbolEffect(.bounce, value:)` fires when the rating changes.
    @ViewBuilder private var plexHeartImage: some View {
        let color = MusicService.plex.brandColor
        let fill = plexRating / 10.0
        Image(systemName: "heart")
            .symbolVariant(plexRating > 0 ? .fill : .none)
            .foregroundStyle(
                plexRating == 0
                    ? AnyShapeStyle(color.gradient)
                    : AnyShapeStyle(
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
            )
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
