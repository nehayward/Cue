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
            self.isEnabled(service)
        } set: { newValue in
            self.setFeature(value: newValue, service.title)
        }
    }

    /// A service that isn't in `MediaSearchService.supported` is never
    /// enabled, whatever an older build left in defaults — so a stored
    /// Spotify selection falls out of search, browse, and the tabs on its
    /// own.
    func isEnabled(_ service: MediaSearchService) -> Bool {
        guard service.isSupported, feature(service.title) else { return false }
        // Audiobookshelf is on only once signed in here: there's no Sonos
        // account to find it by, and on an install from before Cue offered
        // it, its flag was never stored, which reads as on — Search and
        // Browse listed a server nobody had set up.
        return service != .audiobookshelf || AudiobookshelfAPI.shared.isConfigured
    }

    /// Switches on the services chosen in onboarding and off the rest, so
    /// Search, Browse and the tabs offer only what's in use. An Apple Music
    /// left out is never read, and never asks for access.
    @MainActor
    func enableOnly(_ chosen: Set<MediaSearchService>) {
        for service in MediaSearchService.supported {
            setFeature(value: chosen.contains(service), service.title)
        }
    }

    /// Disable any service the user no longer has authorized in Sonos.
    /// Unlike `enableOnly` this never re-enables anything, so a
    /// manual "off" choice survives. Called whenever the Services screen
    /// gets a fresh (non-empty) discovery result, so search/browse stop
    /// offering services that can't return playable results.
    @MainActor
    func disableUnauthorizedServices(from installed: Set<SonosServiceType>) {
        for service in MediaSearchService.supported
        where !service.isAuthorized(on: installed) && isEnabled(service) {
            setFeature(value: false, service.title)
        }
    }

    /// Undoes, once, what `disableUnauthorizedServices` did before a service
    /// the device plays on its own counted as authorized: switching Sonos
    /// households switched Apple Music, Plex and TuneIn off, and the Radio
    /// tab with them. Turns each back on if this device can play it. Runs a
    /// single time, so a service switched off by hand afterwards stays off.
    @MainActor
    func restoreDeviceServicesOnce() {
        let key = "dance.cue.restoredDeviceServices"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        for service in [MediaSearchService.apple, .plex, .tuneIn]
        where !isEnabled(service) && service.isAuthorized(on: []) {
            setFeature(value: true, service.title)
        }
    }

    /// The service Search starts on after onboarding: Apple Music first,
    /// then the servers, then radio. Falls back to `.files`, since a folder
    /// on this device needs no account at all.
    static func preferredDefaultService(from chosen: Set<MediaSearchService>) -> MediaSearchService {
        [MediaSearchService.apple, .plex, .subsonic, .tuneIn, .files].first(where: chosen.contains) ?? .files
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
