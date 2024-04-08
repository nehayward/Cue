public struct PlayMode: OptionSet {
    public let rawValue: Int

//    NORMAL / REPEAT_ALL / REPEAT_ONE / SHUFFLE_NOREPEAT / SHUFFLE / SHUFFLE_REPEAT_ONE
    public static let normal = Self(rawValue: 1 << 0)
    public static let shuffle = Self(rawValue: 1 << 1)
    public static let repeatOne = Self(rawValue: 1 << 2)
    public static let repeatAll = Self(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init?(mode: String) {
        switch mode.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "normal":
            self = .normal
        case "repeat_all":
            self = .repeatAll
        case "repeat_one":
            self = .repeatOne
        case "shuffle":
            self = [.shuffle, .repeatAll]
        case "shuffle_norepeat":
            self = .shuffle
        case "shuffle_repeat_one":
            self = [.shuffle, .repeatOne]
        default:
            return nil
        }
    }

    public var sonosMode: String {
        return switch self {
        case .normal:
            "normal"
        case .repeatAll:
            "repeat_all"
        case .repeatOne:
            "repeat_one"
        case [.shuffle, .repeatAll]:
            "shuffle"
        case [.normal, .shuffle]:
            "shuffle_norepeat"
        case [.shuffle, .repeatOne]:
            "shuffle_repeat_one"
        default:
            "normal"
        }
    }
}

extension PlayMode: CustomStringConvertible, CustomDebugStringConvertible {
    static public var debugDescriptions: [(Self, String)] = [
        (.normal, "normal"),
        (.repeatAll, "repeatAll")
    ]

    public var debugDescription: String {
        let result: [String] = Self.debugDescriptions.filter { contains($0.0) }.map { $0.1 }
        let printable = result.joined(separator: ", ")
        return "\(printable)"
    }

    public var description: String {
        let result: [String] = Self.debugDescriptions.filter { contains($0.0) }.map { $0.1 }
        let printable = result.joined(separator: ", ")
        return "\(printable)"
    }
}
