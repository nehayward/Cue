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

    var history: OrderedSet<PlayableContent> {
        get {
            return _playHistory
        }
        set {
            _playHistory = newValue
        }
    }

    @ObservationIgnored @CloudStorage(CloudKeys.playHistory) private var _playHistory: OrderedSet<PlayableContent> = []
}
