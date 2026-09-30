import Foundation

public enum AnalyticEvents: String {
    case viewedPaywall
    case viewedManageSubscription
    case viewedSceneBuilderScreen
    case subscribed
    case createdScene
    case selectedMusicService
    case numberOfDevices
    /// A download was refused by the free song limit. `viewedPaywall` with
    /// `source: downloads` follows if the banner is tapped.
    case downloadLimitReached

    var name: String { self.rawValue }
}

/// Onboarding-funnel events. Kept in its own namespace so the existing
/// `AnalyticEvents` enum doesn't grow unbounded and so Mixpanel naturally
/// groups all `onboarding_*` events together.
public enum OnboardingEvent: String {
    /// Welcome page first appears (sheet presents).
    case started
    /// Answered "Do you have Sonos?" with Yes — the Discovery page is next.
    case answeredHasSonos
    /// Answered "Do you have Sonos?" with No — Sonos stays off and the
    /// device's own services page is next.
    case answeredNoSonos
    /// User tapped Continue on the Discovery page — Local Network prompt
    /// fires next.
    case discoveryStarted
    /// Discovery successfully surfaced at least one Sonos speaker.
    case discoverySucceeded
    /// Discovery resolved to "No Sonos found" (`notFound`) — user can
    /// retry or close.
    case discoveryNotFound
    /// Discovery resolved to "Local Network blocked" (`denied`) — user
    /// must grant permission in Settings.
    case discoveryDenied
    /// User landed on the Music Services step.
    case viewedServices
    /// User landed on the Plex setup step — only shown when Plex was found
    /// among the user's authorized Sonos services.
    case viewedPlex
    /// User submitted an email on the newsletter step (server returned
    /// `subscribed` or `already_subscribed`).
    case emailSubscribed
    /// User tapped Skip on the newsletter step.
    case emailSkipped
    /// Onboarding sheet dismissed with `hasOnboarded = true` — user
    /// completed the flow.
    case completed
    /// Onboarding closed without completing (X tapped from the discovery
    /// "No Sonos found" state).
    case bailed

    /// Serialized as `onboarding_<raw>` so all onboarding events live
    /// under a single Mixpanel prefix.
    var name: String { "onboarding_\(self.rawValue)" }
}
