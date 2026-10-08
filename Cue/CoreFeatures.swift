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
        service.isSupported && feature(service.title)
    }

    /// Sync Cue's per-service enabled flags to whatever the user has actually
    /// authorized in Sonos. Called from onboarding once discovery succeeds so
    /// the user doesn't see search/browse tabs for services they can't use.
    ///
    /// Self-hosted services answer from their in-Cue setup. Every other
    /// service — including Apple Music — is gated on the Sonos installed
    /// set, because plenty of users don't subscribe to Apple Music and
    /// would otherwise see a tab that returns no playable results.
    @MainActor
    func syncEnabledServices(from installed: Set<SonosServiceType>) {
        for service in MediaSearchService.supported {
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

    /// Preferred default service after discovery — Apple Music first, then
    /// Plex, then radio. Falls back to `.files` when nothing is installed
    /// (e.g. no Sonos system found, or none of the supported services are
    /// set up), since a folder on this device needs no account at all.
    static func preferredDefaultService(from installed: Set<SonosServiceType>) -> MediaSearchService {
        if installed.contains(.appleMusic) { return .apple }
        if installed.contains(.plex) { return .plex }
        if installed.contains(.tunein) { return .tuneIn }
        return .files
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
