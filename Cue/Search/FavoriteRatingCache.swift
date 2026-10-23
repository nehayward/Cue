import Observation
import UIKit

/// Favorite state set during this session, so a row shows the heart the
/// moment it is tapped rather than waiting for the next fetch. Keyed by
/// content id and shared across services — Plex stores a 0–10 rating, the
/// others just "is it favorited", and every reader only asks whether it is
/// above zero.
@Observable
final class FavoriteRatingCache {
    static let shared = FavoriteRatingCache()

    private(set) var ratings: [String: Double] = [:]

    init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.ratings.removeAll() }
    }

    func set(_ rating: Double, for id: String) {
        // Unchanged: no update for every row reading the ratings.
        guard ratings[id] != rating else { return }
        if ratings.count > 500 { ratings.removeAll() }
        ratings[id] = rating
    }
}
