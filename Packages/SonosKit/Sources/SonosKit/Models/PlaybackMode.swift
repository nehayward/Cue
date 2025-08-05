public struct PlayMode: Codable, OptionSet, Hashable, Sendable {
    public let rawValue: Int

    // MARK: - Flags
    public static let normal: PlayMode = []
    public static let shuffle = PlayMode(rawValue: 1 << 0)
    public static let repeatOne = PlayMode(rawValue: 1 << 1)
    public static let repeatAll = PlayMode(rawValue: 1 << 2)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    // MARK: - Initializer from Sonos Mode String
    public init?(mode: String) {
        switch mode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "NORMAL":
            self = .normal
        case "REPEAT_ALL":
            self = [.repeatAll]
        case "REPEAT_ONE":
            self = [.repeatOne]
        case "SHUFFLE_NOREPEAT":
            self = [.shuffle]
        case "SHUFFLE":
            self = [.shuffle, .repeatAll]
        case "SHUFFLE_REPEAT_ONE":
            self = [.shuffle, .repeatOne]
        default:
            return nil
        }
    }

    // MARK: - Sonos Mode String
    public var sonosMode: String {
        switch self {
        case .normal:
            return "NORMAL"
        case [.repeatAll]:
            return "REPEAT_ALL"
        case [.repeatOne]:
            return "REPEAT_ONE"
        case [.shuffle]:
            return "SHUFFLE_NOREPEAT"
        case [.shuffle, .repeatAll]:
            return "SHUFFLE"
        case [.shuffle, .repeatOne]:
            return "SHUFFLE_REPEAT_ONE"
        default:
            return "NORMAL" // fallback
        }
    }

    // MARK: - Helpers
    public var isShuffleEnabled: Bool {
        contains(.shuffle)
    }
    
    public var isRepeatEnabled: Bool {
        contains(.repeatOne) || contains(.repeatAll)
    }
    
    public var isRepeatOneEnabled: Bool {
        contains(.repeatOne)
    }

    public var isRepeatAllEnabled: Bool {
        contains(.repeatAll)
    }
}

extension PlayMode: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { sonosMode }
    public var debugDescription: String { sonosMode }
}
