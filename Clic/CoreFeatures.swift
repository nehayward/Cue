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

    /// Sync Clic's per-service enabled flags to whatever the user has actually
    /// authorized in Sonos. Called from onboarding once discovery succeeds so
    /// the user doesn't see search/browse tabs for services they can't use.
    ///
    /// `.library` and `.apple` stay enabled regardless — both work via local
    /// playback / MusicKit and don't depend on a Sonos service authorization.
    @MainActor
    func syncEnabledServices(from installed: Set<SonosServiceType>) {
        let mapping: [(MediaSearchService, SonosServiceType?)] = [
            (.apple, .appleMusic),
            (.library, nil),         // local — always available
            (.plex, .plex),
            (.spotify, .spotify),
            (.tidal, .tidal),
            (.tuneIn, .tunein),
            (.soundcloud, .soundcloud)
        ]

        for (service, sonosType) in mapping {
            let enabled: Bool
            if service == .apple || service == .library {
                enabled = true
            } else if let sonosType {
                enabled = installed.contains(sonosType)
            } else {
                enabled = true
            }
            setFeature(value: enabled, service.title)
        }
    }

    /// Preferred default service after discovery — Spotify first, then Apple,
    /// then whatever else the user has, falling back to Apple Music for the
    /// no-Sonos / first-launch case.
    static func preferredDefaultService(from installed: Set<SonosServiceType>) -> MediaSearchService {
        if installed.contains(.spotify) { return .spotify }
        if installed.contains(.appleMusic) { return .apple }
        if installed.contains(.tidal) { return .tidal }
        if installed.contains(.plex) { return .plex }
        if installed.contains(.soundcloud) { return .soundcloud }
        if installed.contains(.tunein) { return .tuneIn }
        return .apple
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
