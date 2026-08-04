import MusicSearchKit
import SonosKit
import SwiftUI

struct LikeButtonView: View {
    var group: GroupRoom

    @Environment(PlexRatingCache.self) private var plexRatingCache
    @State private var isFavorite = false
    @State private var plexRating: Double = 0
    @State private var favoriteAnimationTrigger = 0

    // Observable so likes toggled from the Live Activity (whose intents run in
    // this process) update this button live.
    private let favoriteStore = LiveActivityFavoriteStore.shared

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
                Task { await MusicSearchService.shared.setFavorite(newRating > 0, trackID: trackID, service: .plex) }
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
                LiveActivityFavoriteStore.shared.set(rating > 0, for: trackID)
                var transaction = Transaction(animation: .none)
                transaction.disablesAnimations = true
                withTransaction(transaction) { plexRating = rating }
            }
            .onChange(of: favoriteStore.favorites[trackID]) { _, newValue in
                // Like toggled from the Live Activity — mirror it here.
                guard let newValue, newValue != (plexRating > 0) else { return }
                let rating = newValue ? 10.0 : 0.0
                plexRating = rating
                plexRatingCache.set(rating, for: trackID)
                if newValue { favoriteAnimationTrigger += 1 }
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
            .onChange(of: favoriteStore.favorites[trackID]) { _, newValue in
                // Like toggled from the Live Activity — mirror it here.
                guard let newValue, newValue != isFavorite else { return }
                isFavorite = newValue
                if newValue { favoriteAnimationTrigger += 1 }
            }
            .tint(service.brandColor.gradient)

        case .pandora:
            ThumbsRatingView(group: group)

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

    // Favorite reads/writes go through MusicSearchService.isFavorite/setFavorite,
    // which also update LiveActivityFavoriteStore so the Live Activity heart
    // stays in sync with likes made here.
    private func performAction(service: MusicService, favorite: Bool) async {
        await MusicSearchService.shared.setFavorite(favorite, trackID: trackID, service: service)
    }

    private func checkFavorite(service: MusicService) async -> Bool {
        await MusicSearchService.shared.isFavorite(trackID: trackID, service: service)
    }
}
