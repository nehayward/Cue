import Foundation
import Observation
import CloudStorage
import OrderedCollections
import Defaults
import SonosKit
import SwiftUI

@MainActor
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
}
