import Defaults
import Foundation
import Observation
import SonosKit
import SubscriptionKit

@Observable
final class CoreFeatures {
    var nowPlaying: Bool {
        get {
            feature(feature: .nowPlaying)
        }
        set {
            setFeature(value: newValue, feature: .nowPlaying)
        }
    }

    private func feature(feature: Features) -> Bool {
        UserDefaults.standard.bool(forKey: feature.key)
    }

    private func setFeature(value: Bool, feature: Features) {
        UserDefaults.standard.setValue(value, forKey: feature.key)
    }
}
