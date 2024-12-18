import Defaults
import Foundation
import Observation
import SonosKit
import SubscriptionKit

@Observable
final class BetaFeatures {
    var tidalFeature: Bool {
        get {
            feature(feature: .tidalSupport) && SubscriptionService.shared.subscription.isActive
        }
        set {
            setFeature(value: newValue, feature: .tidalSupport)
        }
    }

    private func feature(feature: FeatureKeys) -> Bool {
        UserDefaults.standard.bool(forKey: feature.key)
    }

    private func setFeature(value: Bool, feature: FeatureKeys) {
        UserDefaults.standard.setValue(value, forKey: feature.key)
    }
}
