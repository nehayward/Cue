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
    /// Keeping more than `DownloadManager.freeSongLimit` songs at once,
    /// on this device and the watch together.
    case unlimitedDownloads
    /// Keeping a book on this device or the watch.
    case bookDownloads
    /// Cue on a car's screen: browsing and playing from CarPlay.
    case carPlay
    case lastFM

    var id: String { rawValue }

    /// What keeping `item` needs: a book's own gate, else downloads.
    static func download(of item: PlayableContent) -> GatedFeature {
        item.content.type == .audiobook ? .bookDownloads : .downloads
    }

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
        case .unlimitedDownloads: "Unlimited Downloads"
        case .bookDownloads: "Book Downloads"
        case .carPlay: "CarPlay"
        case .lastFM: "Last.fm"
        }
    }

    var requirement: FeatureGate.Requirement {
        switch self {
        case .allRooms, .scenes, .liveActivities, .lockScreenNowPlaying, .hardwareVolumeButtons, .unlimitedDownloads, .bookDownloads:
            .superTier
        case .files, .onDevicePlayback, .downloads, .carPlay:
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

    /// Debug-only: read as the free tier whatever the subscription says.
    /// A Debug build on a device is granted Super (its receipt reads as
    /// TestFlight's), so without this the free tier can't be seen on the
    /// phone. Also on at launch with `-dance.cue.actsAsFreeTier YES`, or the
    /// `Cue [Free]` scheme's `SUBSCRIBED=false`. The Shortcuts actions read
    /// the App Group's answer, not this.
    private(set) var actsAsFreeTier = false
    private static let actsAsFreeTierKey = "dance.cue.actsAsFreeTier"

    init(subscription: SubscriptionService = .shared, flags: RemoteFeatureFlags = .shared) {
        self.subscription = subscription
        self.flags = flags
        #if DEBUG
        overrides = Self.loadOverrides()
        actsAsFreeTier = UserDefaults.standard.bool(forKey: Self.actsAsFreeTierKey)
            || ProcessInfo.processInfo.environment["SUBSCRIBED"] == "false"
        #endif
    }

    // MARK: - Reading

    /// Whether this device has Cue Super. Anything that asks about Super
    /// rather than about a feature (the Settings card, `cue://subscribe`)
    /// reads this, so the debug free tier reaches it too.
    var hasSuper: Bool {
        #if DEBUG
        if actsAsFreeTier { return false }
        #endif
        return subscription.subscription.isActive
    }

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

    /// The free tier's room: the first active one by name, which is the
    /// top speaker row in Play On. Its group is the one group the free tier
    /// plays on, as Clic's first row is; other rooms can still join it.
    /// Read from the rooms rather than the groups' sort, which can put
    /// whatever is playing first and would move the free group with it.
    /// `nil` with no rooms known yet.
    @MainActor
    var freeRoomID: String? {
        SonosService.shared.sortedRooms.first { $0.state == .active }?.id
    }

    /// Whether the free tier may play on and control this group: Super, or
    /// the group holding `freeRoomID`. With no rooms known there is nothing
    /// to hold back yet. By coordinator: a group is equal only to itself,
    /// and a caller may hold an instance a topology refresh has replaced.
    @MainActor
    func isGroupUnlocked(_ coordinatorID: String) -> Bool {
        if isAvailable(.allRooms) { return true }
        guard let freeRoomID else { return true }
        let free = SonosService.shared.groups.first { group in group.rooms.contains { $0.id == freeRoomID } }
        return free?.coordinatorID == coordinatorID
    }

    private func availability(of requirement: Requirement) -> Availability {
        switch requirement {
        case .free:
            return .available
        case .superTier:
            return hasSuper ? .available : .needsSuper
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

    func setActsAsFreeTier(_ value: Bool) {
        actsAsFreeTier = value
        UserDefaults.standard.set(value, forKey: Self.actsAsFreeTierKey)
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
