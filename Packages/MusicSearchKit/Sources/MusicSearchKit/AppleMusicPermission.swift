import Foundation
import MusicKit

/// The one way Cue asks for Apple Music access. Every Apple Music call asks
/// before it runs, and a new install's Browse opens on the Apple library, so
/// the system's alert came up over onboarding's welcome screen before anyone
/// had said they use Apple Music. While the alert is held (from launch until
/// onboarding closes), a call that would put it up answers `.notDetermined`
/// instead and does nothing; `ask()`, for the listener choosing Apple Music,
/// always asks.
public enum AppleMusicPermission {
    /// Posted when the alert stops being held and after `ask()`, so a
    /// screen that read nothing while it was held can read again.
    public static let didChange = Notification.Name("dance.cue.appleMusicPermissionDidChange")

    /// Set at launch while onboarding hasn't run, cleared as it closes.
    public static var isHeld = false {
        didSet {
            guard oldValue, !isHeld else { return }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// The current answer, asking first unless the alert is held.
    public static func request() async -> MusicAuthorization.Status {
        if isHeld, MusicAuthorization.currentStatus == .notDetermined {
            return .notDetermined
        }
        return await MusicAuthorization.request()
    }

    /// Asks whether or not the alert is held: the listener chose Apple Music.
    @discardableResult
    public static func ask() async -> MusicAuthorization.Status {
        let status = await MusicAuthorization.request()
        await MainActor.run {
            NotificationCenter.default.post(name: didChange, object: nil)
        }
        return status
    }
}
