import Foundation

/// Launch arguments / env vars used to drive the onboarding flow during
/// development and QA. All flags are read at access time, so flipping them
/// in the scheme takes effect on the next launch.
enum OnboardingDebug {
    /// Pass `-ForceOnboarding` as a launch argument (or set `FORCE_ONBOARDING=1`
    /// in the scheme env) to present onboarding on every launch and skip the
    /// `hasOnboarded` write, so the simulator keeps showing it.
    static var forceShow: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-ForceOnboarding") || env["FORCE_ONBOARDING"] == "true"
    }

    /// Pass `-MockNoServices` as a launch argument (or set `MOCK_NO_SERVICES=true`)
    /// to skip the real service lookup and pretend the user's Sonos has nothing
    /// installed — useful for previewing the "Add a music service in Sonos" empty
    /// state without changing the real system.
    static var mockNoServices: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-MockNoServices") || env["MOCK_NO_SERVICES"] == "true"
    }

    /// Pass `-MockNoGroups` as a launch argument (or set `MOCK_NO_GROUPS=true`)
    /// to skip real discovery on the discovery step and force the "No Sonos
    /// system found" state after a brief delay — useful for previewing the
    /// notFound recovery UI without disconnecting from your real Sonos system.
    static var mockNoGroups: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-MockNoGroups") || env["MOCK_NO_GROUPS"] == "true"
    }
}
