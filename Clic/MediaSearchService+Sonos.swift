import MusicSearchKit
import SonosKit

/// Single source of truth for which Sonos-side service a Clic
/// `MediaSearchService` corresponds to. Used by onboarding's enabled-services
/// sync and the Services preference screen, so both agree on what
/// "authorized in Sonos" means. When you add a new music backend, add its
/// case here and everything downstream picks it up.
extension MediaSearchService {
    /// The Sonos service that must be authorized (in the Sonos app) for this
    /// Clic service to return playable results. `nil` means no Sonos account
    /// is involved — the local Library works without one.
    var sonosServiceType: SonosServiceType? {
        switch self {
        case .apple: .appleMusic
        case .library: nil
        case .plex: .plex
        case .spotify: .spotify
        case .tidal: .tidal
        case .tuneIn: .tunein
        case .soundcloud: .soundcloud
        case .deezer: .deezer
        case .sonosRadio: .sonosRadio
        }
    }

    /// Whether the user can actually play from this service, given the set of
    /// services discovered on their Sonos system. Services with no Sonos
    /// counterpart (Library) are always available.
    func isAuthorized(on installed: Set<SonosServiceType>) -> Bool {
        guard let sonosServiceType else { return true }
        return installed.contains(sonosServiceType)
    }
}
