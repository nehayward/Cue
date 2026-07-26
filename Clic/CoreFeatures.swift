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
    /// `.library` always stays enabled (local files don't need authorization).
    /// Every other service — including Apple Music — is gated on the Sonos
    /// installed set, because plenty of users don't subscribe to Apple Music
    /// and would otherwise see a tab that returns no playable results.
    @MainActor
    func syncEnabledServices(from installed: Set<SonosServiceType>) {
        for service in MediaSearchService.allCases {
            setFeature(value: service.isAuthorized(on: installed), service.title)
        }
    }

    /// Disable any service the user no longer has authorized in Sonos.
    /// Unlike `syncEnabledServices` this never re-enables anything, so a
    /// manual "off" choice survives. Called whenever the Services screen
    /// gets a fresh (non-empty) discovery result, so search/browse stop
    /// offering services that can't return playable results.
    @MainActor
    func disableUnauthorizedServices(from installed: Set<SonosServiceType>) {
        for service in MediaSearchService.allCases
        where !service.isAuthorized(on: installed) && isEnabled(service) {
            setFeature(value: false, service.title)
        }
    }

    /// Preferred default service after discovery — Apple Music first, then
    /// Spotify, then whatever else the user has authorized. Falls back to
    /// `.library` when nothing is installed (e.g. no Sonos system found, or
    /// none of the supported services are set up), since that's the one
    /// service we can always guarantee works.
    static func preferredDefaultService(from installed: Set<SonosServiceType>) -> MediaSearchService {
        if installed.contains(.appleMusic) { return .apple }
        if installed.contains(.spotify) { return .spotify }
        if installed.contains(.tidal) { return .tidal }
        if installed.contains(.plex) { return .plex }
        if installed.contains(.soundcloud) { return .soundcloud }
        if installed.contains(.deezer) { return .deezer }
        if installed.contains(.tunein) { return .tuneIn }
        if installed.contains(.pandora) { return .pandora }
        if installed.contains(.sonosRadio) { return .sonosRadio }
        return .library
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
