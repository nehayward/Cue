
public enum RoomState: Hashable {
    case active
    case sleeping
    case poweredOff
    case unknown

    init(reason: String) {
        switch reason.lowercased() {
        case "powered off":
            self = .poweredOff
        case "sleeping":
            self = .sleeping
        default:
            self = .unknown
        }
    }

    public var reason: String {
        switch self {
        case .active:
            "Active"
        case .sleeping:
            "Sleeping"
        case .poweredOff:
            "Off"
        case .unknown:
            "Unknown"
        }
    }

    public var systemSymbol: String {
        switch self {
        case .active:
            ""
        case .sleeping:
            "moon.zzz.fill"
        case .poweredOff:
            "power.circle.fill"
        case .unknown:
            ""
        }
    }
}
