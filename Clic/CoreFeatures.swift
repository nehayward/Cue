import Defaults
import Foundation
import Observation
import SonosKit
import SubscriptionKit
import MusicSearchKit
import SwiftUI

@Observable
final class CoreFeatures {
    static let shared = CoreFeatures()
    
    var features: [String: Bool] = [:]
    
    init() {
        // Load all features from UserDefaults
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if let value = UserDefaults.standard.object(forKey: key) as? Bool {
                features[key] = value
            }
        }
    }
    
    var nowPlaying: Bool {
        get {
#if targetEnvironment(macCatalyst)
            return false
#endif
            return feature(feature: .nowPlaying)
        }
        set { setFeature(value: newValue, feature: .nowPlaying) }
    }
    
    func enabledServices(_ service: MediaSearchService) -> Binding<Bool> {
        Binding {
            self.feature(service.title)
        } set: { newValue in
            self.setFeature(value: newValue, service.title)
        }
    }

    func isEnabled(_ service: MediaSearchService) -> Bool {
        feature(service.title)
    }

    private func feature(feature: FeatureKeys) -> Bool {
        features[feature.key] ?? UserDefaults.standard.bool(forKey: feature.key)
    }

    private func setFeature(value: Bool, feature: FeatureKeys) {
        features[feature.key] = value
        UserDefaults.standard.setValue(value, forKey: feature.key)
    }

    private func feature(_ feature: String) -> Bool {
        features[feature] ?? UserDefaults.standard.object(forKey: feature) as? Bool ?? true
    }

    private func setFeature(value: Bool, _ feature: String) {
        features[feature] = value
        UserDefaults.standard.setValue(value, forKey: feature)
    }
}
