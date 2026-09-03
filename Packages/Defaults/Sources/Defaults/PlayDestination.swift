import Foundation

/// Where a share plays: this device, or one Sonos group.
///
/// Lives here rather than beside either screen because both the share
/// extension and the app's play sheet read and write it, and they are separate
/// processes — the extension's own `UserDefaults.standard` is a different
/// container, and its process ends with the sheet, so the shared app-group
/// suite is the only thing that carries the choice from one share to the next.
public enum PlayDestination: Equatable, Hashable, Sendable {
    case device
    /// A group's *coordinator* id, not its `GroupRoom.id`: the latter carries
    /// the Sonos group session and changes whenever rooms are regrouped, so a
    /// remembered group would stop matching the first time the user regrouped.
    case group(String)
}

public extension PlayDestination {
    /// Never collides with a stored group id — those are `RINCON_…` room ids.
    private static var deviceToken: String { "device" }

    private static var store: UserDefaults { GroupStorageKeys.defaults }

    static var remembered: PlayDestination? {
        guard let raw = store.string(forKey: GroupStorageKeys.playActionDestination) else {
            return nil
        }
        return raw == deviceToken ? .device : .group(raw)
    }

    func remember() {
        let raw: String = switch self {
        case .device: Self.deviceToken
        case let .group(id): id
        }
        Self.store.set(raw, forKey: GroupStorageKeys.playActionDestination)
    }

    var groupID: String? {
        if case let .group(id) = self { return id }
        return nil
    }
}
