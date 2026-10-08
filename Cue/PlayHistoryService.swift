import Foundation
import Observation
import CloudStorage
import OrderedCollections
import Defaults
import SonosKit
import SwiftUI

@Observable
final class PlayHistoryService: ObservableObject {
    static var shared = PlayHistoryService()

    @ObservationIgnored var history: OrderedSet<PlayableContent> {
        get {
            access(keyPath: \.history)
            return _playHistory
        }
        set {
            withMutation(keyPath: \.history) {
                _playHistory = newValue
            }
        }
    }

    @ObservationIgnored @CloudStorage(CloudKeys.playHistory) private var _playHistory: OrderedSet<PlayableContent> = []

    /// The most plays kept. The history syncs through iCloud key-value
    /// storage, which takes at most 1 MB a key (a play is about 1 KB
    /// encoded), and every read compares the whole stored list and every
    /// write encodes it: it used to grow with every play, for good.
    static let limit = 200

    /// Puts `content` at the top of the history, once, in a single write —
    /// a remove and an insert each encoded and stored the whole list.
    func record(_ content: PlayableContent) {
        var updated = history
        updated.remove(content)
        updated.insert(content, at: 0)
        if updated.count > Self.limit {
            updated.removeLast(updated.count - Self.limit)
        }
        history = updated
    }
}
