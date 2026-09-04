import MusicSearchKit
import SonosKit
import SwiftUI

struct LikeButtonView: View {
    /// The group whose current track this rates — the Sonos player.
    var group: GroupRoom?
    /// What this device is playing — the local player. One or the other.
    var content: PlayableContent?

    init(group: GroupRoom) {
        self.group = group
    }

    init(content: PlayableContent) {
        self.content = content
    }

    @Environment(FavoriteRatingCache.self) private var favoriteRatingCache
    @State private var favoriteAnimationTrigger = 0
    /// The song whose first read has landed. Until then the button isn't
    /// showing a *change*, it's showing what was always true — see the bounce.
    @State private var seededTrackID: String?

    // Observable so likes toggled from the Live Activity (whose intents run in
    // this process) update this button live.
    private let favoriteStore = LiveActivityFavoriteStore.shared

    /// The same key on both surfaces: a Sonos track's id is the catalog id
    /// its `PlayableContent` carries, so a like made here shows on the
    /// speaker's player too.
    private var trackID: String { group?.coordinatorRoom.track.trackID ?? content?.id ?? "" }

    private var service: MusicService { group?.coordinatorRoom.track.musicService ?? content?.content.service ?? .unknown }

    /// What the first-read tasks key on — the track's identity on either
    /// surface, so a new track re-reads and a re-render doesn't.
    private var trackKey: String { group?.coordinatorRoom.track.id ?? content?.id ?? "" }

    /// Read straight from the store rather than mirrored into `@State`.
    ///
    /// `MusicSearchService.isFavorite`/`setFavorite` both write
    /// `LiveActivityFavoriteStore`, whichever surface called them — this button,
    /// a context menu, the Live Activity's own intent — and the store is
    /// `@Observable`, so a copy here bought nothing and could disagree with it.
    /// The `onChange` that kept the copy in step was re-implementing observation
    /// by hand, including a `newValue != isFavorite` guard that only existed
    /// because there were two values to compare in the first place.
    private var isFavorite: Bool { favoriteStore.favorites[trackID] ?? false }

    /// Plex needs both stores: the cache carries the 0–10 value the partial
    /// heart fill draws, and the store carries whether it's favorited at all —
    /// which is the only thing a Live Activity like can write. While they agree,
    /// the cache's magnitude wins; when they don't, the store is newer.
    private var plexRating: Double {
        let cached = favoriteRatingCache.ratings[trackID] ?? 0
        guard let favorited = favoriteStore.favorites[trackID] else { return cached }
        return favorited == (cached > 0) ? cached : (favorited ? 10 : 0)
    }

    var body: some View {
        switch service {
        case .plex:
            Button {
                let newRating = plexRating > 0 ? 0.0 : 10.0
                // Both, synchronously: `setFavorite` writes the store too, but a
                // hop later — and until it lands the two would disagree, which
                // `plexRating` resolves in the store's favour and would show the
                // old value back to the user mid-tap.
                // Before the writes: a tap is always a change worth bouncing,
                // even if it lands before the first read has come back.
                seededTrackID = trackID
                favoriteRatingCache.set(newRating, for: trackID)
                favoriteStore.set(newRating > 0, for: trackID)
                HapticManager.shared.fireHaptic(newRating > 0 ? .notification(.success) : .selection)
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
            .task(id: trackKey) {
                let rating = await MusicSearchService.shared.getPlexTrackRating(trackID: trackID) ?? 0
                favoriteRatingCache.set(rating, for: trackID)
                favoriteStore.set(rating > 0, for: trackID)
                seededTrackID = trackID
            }
            .onChange(of: plexRating > 0, bounce)
            .tint(MusicService.plex.brandColor.gradient)

        case .spotify, .soundcloud, .apple, .deezer, .subsonic:
            Button {
                let newFavorite = !isFavorite
                // Optimistic, and synchronous so the heart fills on the tap
                // rather than a hop later. `setFavorite` writes the same value.
                // Seed first: a tap is always a change worth bouncing, even if
                // it lands before the first read has come back.
                seededTrackID = trackID
                favoriteStore.set(newFavorite, for: trackID)
                // Subsonic rows draw their heart from the rating cache, so
                // keep it in step with a like made from here.
                if service == .subsonic { favoriteRatingCache.set(newFavorite ? 1 : 0, for: trackID) }
                HapticManager.shared.fireHaptic(newFavorite ? .notification(.success) : .selection)
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
            .task(id: trackKey) {
                // The return value is unused on purpose: `isFavorite(trackID:
                // service:)` records what it read in the store, which is what
                // this button draws from.
                _ = await checkFavorite(service: service)
                seededTrackID = trackID
            }
            .onChange(of: isFavorite, bounce)
            .tint(service.brandColor.gradient)

        case .pandora:
            // Pandora only plays on a speaker, so there is always a group.
            if let group {
                ThumbsRatingView(group: group)
            }

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

    /// The one place the heart bounces, whatever moved the value — this button,
    /// a context menu, or the Live Activity's own intent. Previously the tap and
    /// the mirroring `onChange` each bumped it, which is workable only while
    /// they're the only two ways it can change.
    ///
    /// Nothing bounces until the first read for this song has landed:
    /// `nil → true` from that read isn't a change the user made, and bouncing it
    /// would mean opening the player on an already-liked song animates for no
    /// reason.
    private func bounce(_ oldValue: Bool, _ newValue: Bool) {
        guard newValue, seededTrackID == trackID else { return }
        favoriteAnimationTrigger += 1
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
