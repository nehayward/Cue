import Defaults
import Foundation

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case general
    case message(_ message: String)
    /// Super is locked on this device. Says why, from this device's answer
    /// (`UserDefaults.superUntil`), so someone who paid isn't told to subscribe.
    case superRequired

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .message(message): return "Error: \(message)"
        case .general: return "Failed"
        case .superRequired:
            switch GroupStorageKeys.defaults.superUntil {
            case nil:
                return "Open Cue once on this device to finish setting up Super."
            case let until? where until != .distantPast:
                return "Your Super subscription has ended. Renew it in Cue."
            default:
                return "Subscribe to Super in Cue to use this action."
            }
        }
    }
}
