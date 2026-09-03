import Foundation
import MusicSearchKit

/// Cross-process cache of favorite state keyed by `Track.trackID`, backed by the
/// shared app group so the main app, the widget extension, and Live Activity
/// intents all read/write the same value.
///
/// The Live Activity is a snapshot driven by `ContentState`, and the favorite
/// toggle runs in an App Intent. This store is the single source of truth all
/// sides read so the heart reflects the right state and an optimistic toggle
/// isn't clobbered by a refresh in another process. It is populated lazily when
/// a track first appears and updated optimistically when the user taps like.
@Observable
public final class LiveActivityFavoriteStore: @unchecked Sendable {
    public static let shared = LiveActivityFavoriteStore()

    @ObservationIgnored private let defaults = UserDefaults(suiteName: "group.dance.cue")
    @ObservationIgnored private let key = "liveActivityFavorites"
    @ObservationIgnored private let lock = NSLock()

    /// Observable in-memory mirror of the app-group defaults, seeded at init.
    /// Live Activity intents run in the app's process, so a like tapped on the
    /// activity mutates this instance and any SwiftUI view reading it (e.g. the
    /// player's like button) updates live.
    public private(set) var favorites: [String: Bool]

    private init() {
        favorites = (UserDefaults(suiteName: "group.dance.cue")?
            .dictionary(forKey: "liveActivityFavorites") as? [String: Bool]) ?? [:]
    }

    public func get(_ trackID: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return favorites[trackID]
    }

    public func set(_ isFavorite: Bool, for trackID: String) {
        lock.lock()
        defer { lock.unlock() }
        if favorites.count > 500 { favorites.removeAll() }
        favorites[trackID] = isFavorite
        defaults?.set(favorites, forKey: key)
    }
}

public extension MusicSearchService {
    /// Returns whether the given track is currently favorited on its service.
    /// Covers every service in `MusicService.supportsFavoriteTrack`. Also
    /// records the fetched value in `LiveActivityFavoriteStore` so the Live
    /// Activity heart stays in sync with whatever the app has last seen.
    func isFavorite(trackID: String, service: MusicService) async -> Bool {
        let value: Bool
        switch service {
        case .spotify:
            value = await isSpotifyTrackSaved(id: trackID)
        case .soundcloud:
            value = await isSoundCloudTrackLiked(id: trackID) ?? false
        case .apple:
            value = (try? await AppleMusicAPI.shared.isFavorite(songId: trackID)) ?? false
        case .deezer:
            value = await isDeezerTrackLiked(id: trackID)
        case .plex:
            value = (await getPlexTrackRating(trackID: trackID) ?? 0) > 0
        case .subsonic:
            value = await isSubsonicTrackLiked(id: trackID)
        default:
            return false
        }
        LiveActivityFavoriteStore.shared.set(value, for: trackID)
        return value
    }

    /// Sets the favorite state for the given track on its service. Writes the
    /// new value to `LiveActivityFavoriteStore` up front (optimistically) so
    /// the Live Activity reflects the change on its next refresh regardless of
    /// where the toggle happened (player, context menu, or the activity itself).
    @discardableResult
    func setFavorite(_ favorite: Bool, trackID: String, service: MusicService) async -> Bool {
        guard service.supportsFavoriteTrack else { return false }
        LiveActivityFavoriteStore.shared.set(favorite, for: trackID)
        switch service {
        case .spotify:
            return favorite ? await saveSpotifyTrack(id: trackID) : await deleteSpotifyTrack(id: trackID)
        case .soundcloud:
            return favorite ? await likeSoundCloudTrack(id: trackID) : await unlikeSoundCloudTrack(id: trackID)
        case .apple:
            return ((try? await AppleMusicAPI.shared.updateFavoriteStatus(songId: trackID, favorite: favorite)) != nil)
        case .deezer:
            return favorite ? await likeDeezerTrack(id: trackID) : await unlikeDeezerTrack(id: trackID)
        case .plex:
            return await ratePlexTrack(trackID: trackID, rating: favorite ? 10 : 0)
        case .subsonic:
            return favorite ? await likeSubsonicTrack(id: trackID) : await unlikeSubsonicTrack(id: trackID)
        default:
            return false
        }
    }
}
