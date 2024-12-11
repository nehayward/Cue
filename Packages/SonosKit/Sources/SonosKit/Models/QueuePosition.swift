public enum QueuePosition {
    case front
    case end
    case next
    case now
    case replace
    
    /// A user-friendly title describing the queue position.
    public var title: String {
        switch self {
        case .front:
            return "Added to the front of the queue"
        case .end:
            return "Playing last"
        case .next:
            return "Playing next"
        case .now:
            return "Playing now"
        case .replace:
            return "Queue replaced"
        }
    }
}
