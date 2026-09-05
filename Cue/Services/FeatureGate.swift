import Analytics
import Foundation
import Observation
import SonosKit
import SubscriptionKit

/// Everything the app can hold back, one case per gate. A feature's
/// `requirement` is the single place that says what unlocks it: change it
/// here and every call site — the greyed row, the badge, the paywall on
/// tap — follows.
///
/// Add a case for anything that might ever be held back, even while it is
/// free: the call sites then exist, and gating it later is one line.
enum GatedFeature: String, CaseIterable, Identifiable, Sendable {
    /// Every room beyond the first. The free tier controls one group.
    case allRooms
    case scenes
    case liveActivities
    case lockScreenNowPlaying
    /// The device's volume buttons driving a speaker, part of Lock Screen
    /// Now Playing.
    case hardwareVolumeButtons
    /// The Files provider: a folder of music on this device or in iCloud.
    case files
    /// Playing on this device instead of a speaker.
    case onDevicePlayback
    /// Keeping Plex, Subsonic and iCloud Drive tracks on this device.
    case downloads
    case lastFM

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allRooms: "Every Room"
        case .scenes: "Scenes"
        case .liveActivities: "Live Activities"
        case .lockScreenNowPlaying: "Lock Screen Now Playing"
        case .hardwareVolumeButtons: "Volume Buttons"
        case .files: "Files"
        case .onDevicePlayback: "Play on This Device"
        case .downloads: "Downloads"
        case .lastFM: "Last.fm"
        }
    }

    var requirement: FeatureGate.Requirement {
        switch self {
        case .allRooms, .scenes, .liveActivities, .lockScreenNowPlaying, .hardwareVolumeButtons:
            .superTier
        case .files, .onDevicePlayback, .downloads:
            .free
        case .lastFM:
            .remoteFlag(.lastFM)
        }
    }
}

/// Answers "can this user use this feature right now", from the
/// subscription, the remote flags and — in debug builds — a per-feature
/// override. Views read it from the environment; services read `shared`.
///
/// Every read goes through `SubscriptionService` and `RemoteFeatureFlags`,
/// both `@Observable`, so a view that asks re-evaluates on purchase, expiry
/// or a flag fetch without anything else to wire.
@Observable
final class FeatureGate {
    static let shared = FeatureGate()

    enum Requirement: Sendable {
        case free
        case superTier
        case remoteFlag(RemoteFeatureFlags.Flag)
        /// Every listed requirement must hold.
        case all([Requirement])
    }

    enum Availability: Equatable, Sendable {
        case available
        /// Unlocked by Cue Super — the paywall is the answer.
        case needsSuper
        /// Turned off by a remote flag: not on offer, not for sale.
        case disabledRemotely
    }

    private let subscription: SubscriptionService
    private let flags: RemoteFeatureFlags

    /// Debug-only: force a feature on or off regardless of what would
    /// unlock it, to see both sides of a gate without a purchase.
    private(set) var overrides: [GatedFeature: Bool] = [:]
    private static let overridesKey = "dance.cue.featureOverrides"

    init(subscription: SubscriptionService = .shared, flags: RemoteFeatureFlags = .shared) {
        self.subscription = subscription
        self.flags = flags
        #if DEBUG
        overrides = Self.loadOverrides()
        #endif
    }

    // MARK: - Reading

    func availability(of feature: GatedFeature) -> Availability {
        #if DEBUG
        if let forced = overrides[feature] {
            return forced ? .available : .needsSuper
        }
        #endif
        return availability(of: feature.requirement)
    }

    func isAvailable(_ feature: GatedFeature) -> Bool {
        availability(of: feature) == .available
    }

    /// Whether the feature is something to sell — the badge and the
    /// greyed row show for this and nothing else.
    func needsSuper(_ feature: GatedFeature) -> Bool {
        availability(of: feature) == .needsSuper
    }

    /// The free tier's one room: the first group in the speaker list.
    /// Kept here so the speaker list and the mini player agree on it.
    func isRoomUnlocked(_ group: GroupRoom, in sorted: [GroupRoom]) -> Bool {
        if isAvailable(.allRooms) { return true }
        guard let index = sorted.firstIndex(of: group) else { return false }
        return index < 1
    }

    private func availability(of requirement: Requirement) -> Availability {
        switch requirement {
        case .free:
            return .available
        case .superTier:
            return subscription.subscription.isActive ? .available : .needsSuper
        case let .remoteFlag(flag):
            return flags.isEnabled(flag) ? .available : .disabledRemotely
        case let .all(requirements):
            for requirement in requirements {
                let availability = availability(of: requirement)
                if availability != .available { return availability }
            }
            return .available
        }
    }

    // MARK: - Acting

    /// For an action that needs the feature: true means go ahead. When
    /// Super would unlock it, the paywall is presented and false comes
    /// back; a remotely disabled feature just returns false.
    @MainActor
    @discardableResult
    func unlock(_ feature: GatedFeature, via router: Router? = nil) -> Bool {
        switch availability(of: feature) {
        case .available:
            return true
        case .needsSuper:
            presentPaywall(via: router ?? Router.main)
            return false
        case .disabledRemotely:
            return false
        }
    }

    @MainActor
    func presentPaywall(via router: Router = .main) {
        HapticManager.shared.fireHaptic(.buttonPress)
        Analytics.shared.track(.viewedPaywall)
        router.fullScreenCover(to: .paywall)
    }

    // MARK: - Debug overrides

    /// `nil` clears the override.
    func setOverride(_ value: Bool?, for feature: GatedFeature) {
        overrides[feature] = value
        Self.saveOverrides(overrides)
    }

    func clearOverrides() {
        overrides = [:]
        Self.saveOverrides(overrides)
    }

    private static func loadOverrides() -> [GatedFeature: Bool] {
        guard let stored = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Bool] else { return [:] }
        var overrides: [GatedFeature: Bool] = [:]
        for (key, value) in stored {
            if let feature = GatedFeature(rawValue: key) { overrides[feature] = value }
        }
        return overrides
    }

    private static func saveOverrides(_ overrides: [GatedFeature: Bool]) {
        let stored = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(stored, forKey: overridesKey)
    }
}
