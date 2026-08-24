import Observation
import UIKit

@Observable
final class PlexRatingCache {
    static let shared = PlexRatingCache()

    private(set) var ratings: [String: Double] = [:]

    init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.ratings.removeAll() }
    }

    func set(_ rating: Double, for id: String) {
        if ratings.count > 500 { ratings.removeAll() }
        ratings[id] = rating
    }
}
