import Defaults
import Foundation
import Observation
import SonosKit
import SubscriptionKit
import MusicSearchKit
import SwiftUI

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
    
    func enabledServices(_ service: MediaSearchService) -> Binding<Bool> {
        Binding {
            self.feature(service.title)
        } set: { newValue in
            self.setFeature(value: newValue, service.title)
        }
    }

    func isEnabled(_ service: MediaSearchService) -> Bool {
        self.feature(service.title)
    }

    private func feature(feature: Features) -> Bool {
        UserDefaults.standard.bool(forKey: feature.key)
    }

    private func setFeature(value: Bool, feature: Features) {
        UserDefaults.standard.setValue(value, forKey: feature.key)
    }

    private func feature(_ feature: String) -> Bool {
        UserDefaults.standard.object(forKey: feature) as? Bool ?? true
    }

    private func setFeature(value: Bool, _ feature: String) {
        UserDefaults.standard.setValue(value, forKey: feature)
    }
}
