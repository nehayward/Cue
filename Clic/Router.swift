import Foundation

enum Router {
    case subscribe
    case device
    case search

    init?(_ host: String) {
        switch host {
        case "subscribe":
            self = .subscribe
        case "device":
            self = .device
        default:
            return nil
        }
    }
}

struct Route: Equatable, Identifiable, Hashable {
    let id: String
    var search: Bool
}
