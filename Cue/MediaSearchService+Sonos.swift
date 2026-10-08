import MusicKit
import MusicSearchKit
import SonosKit

/// Single source of truth for which Sonos-side service a Cue
/// `MediaSearchService` corresponds to. Used by onboarding's enabled-services
/// sync and the Services preference screen, so both agree on what
/// "authorized in Sonos" means. When you add a new music backend, add its
/// case here and everything downstream picks it up.
extension MediaSearchService {
    /// The Sonos service that must be authorized (in the Sonos app) for this
    /// Cue service to return playable results. `nil` means no Sonos account
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
        case .pandora: .pandora
        case .subsonic: nil
        case .files: nil
        }
    }

    /// Non-nil for self-hosted services configured entirely inside Cue (no
    /// Sonos account involved): whether a server is currently set up. Add an
    /// arm here — alongside `managementSheet` — when porting another
    /// direct-HTTP service (e.g. Jellyfin).
    ///
    /// Main-actor: the answers come from main-actor services, and every
    /// reader (the Services screen, the enabled-services sync) is there too.
    @MainActor
    var isConfiguredInCue: Bool? {
        switch self {
        case .subsonic: SubsonicAPI.shared.isConfigured
        case .files: FilesLibraryService.shared.isConfigured
        default: nil
        }
    }

    /// Whether the user can actually play from this service, given the set of
    /// services discovered on their Sonos system. Services with no Sonos
    /// counterpart (Library) are always available; self-hosted services
    /// bypass Sonos entirely and answer from their in-Cue configuration.
    @MainActor
    func isAuthorized(on installed: Set<SonosServiceType>) -> Bool {
        if let isConfiguredInCue { return isConfiguredInCue }
        if signsInInCue { return isAuthorizedOnDevice }
        // Device-first: a service the phone can play on its own is never
        // switched off because the Sonos system in reach doesn't have it —
        // switching households used to turn Apple Music, Plex and TuneIn
        // off, and the Radio tab went with them.
        if isAuthorizedOnDevice { return true }
        guard let sonosServiceType else { return true }
        return installed.contains(sonosServiceType)
    }

    /// Whether this device can play the service without any speaker: TuneIn
    /// needs no account, Apple Music needs MusicKit access, Plex and TIDAL
    /// need Cue's own sign-in.
    @MainActor
    private var isAuthorizedOnDevice: Bool {
        switch self {
        case .tuneIn: true
        case .apple: MusicAuthorization.currentStatus == .authorized
        case .plex: PlexAuthenticator.shared.authToken != nil
        case .tidal: TidalAccount.shared.isSignedIn
        default: false
        }
    }

    /// Signed in to here in Cue rather than in the Sonos app, and not
    /// offered at all until it is: TIDAL. A TIDAL account linked in the
    /// Sonos app alone plays only on speakers, which Cue doesn't offer.
    var signsInInCue: Bool {
        self == .tidal
    }

    /// The in-app management sheet for services configured (at least partly)
    /// in Cue itself rather than the Sonos app. The Services rows open this
    /// on tap.
    var managementSheet: SheetDestination? {
        switch self {
        case .plex: .plexManagement
        case .subsonic: .subsonicManagement
        case .tidal: .tidalManagement
        case .files: .filesManagement
        default: nil
        }
    }
}
