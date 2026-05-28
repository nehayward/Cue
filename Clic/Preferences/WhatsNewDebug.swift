import Foundation

/// Launch arguments / env vars used to drive the in-app "What's New"
/// banner + toolbar dot during development and QA. Read at access time so
/// flipping in the scheme takes effect on the next launch. Mirrors
/// `OnboardingDebug`.
enum WhatsNewDebug {
    /// Pass `-ForceWhatsNew` as a launch argument (or set `FORCE_WHATS_NEW=true`
    /// in the scheme env) to force the banner + toolbar dot to render even when
    /// the user has already seen the current release. Still requires the worker
    /// to have returned 200 for this bundle's version — no data, no banner.
    static var forceShowBanner: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-ForceWhatsNew") || env["FORCE_WHATS_NEW"] == "true"
    }
}
