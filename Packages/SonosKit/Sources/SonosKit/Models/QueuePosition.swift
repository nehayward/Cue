public enum QueuePosition: Codable {
    case front
    case end
    case next
    case now
    case replace
    
    /// A user-friendly title describing the queue position.
    public var title: String {
        switch self {
        case .front:
            return "Add to the front of the queue"
        case .end:
            return "Play last"
        case .next:
            return "Play next"
        case .now:
            return "Play"
        case .replace:
            return "Replace queue"
        }
    }
}
