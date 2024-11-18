
public struct AvailableActions: OptionSet, Sendable {
    public let rawValue: Int

    public static let set = Self(rawValue: 1 << 0)
    public static let stop = Self(rawValue: 1 << 1)
    public static let pause = Self(rawValue: 1 << 2)
    public static let play = Self(rawValue: 1 << 3)
    public static let next = Self(rawValue: 1 << 4)
    public static let previous = Self(rawValue: 1 << 5)
    public static let scrubbable = Self(rawValue: 1 << 6)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init?(actionName: String) {
        switch actionName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "set":
            self = .set
        case "stop":
            self = .stop
        case "pause":
            self = .pause
        case "play":
            self = .play
        case "next":
            self = .next
        case "previous":
            self = .previous
        case "x_dlna_seektime":
            self = .scrubbable
        default:
            return nil
        }
    }
}

extension AvailableActions: CustomStringConvertible, CustomDebugStringConvertible {
    static public let debugDescriptions: [(Self, String)] = [
        (.set, "set"),
        (.stop, "stop"),
        (.pause, "pause"),
        (.play, "play"),
        (.next, "next"),
        (.previous, "previous"),
        (.scrubbable, "scrubbable")
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
