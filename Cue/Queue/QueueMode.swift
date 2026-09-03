enum QueueMode: String, Identifiable, CaseIterable {
    var id: String { self.title }
    
    case full = "full"
    case upNext = "upNext"
    
    var title: String {
        switch self {
        case .full:
            return "Queue"
        case .upNext:
            return "Up Next"
        }
    }
    
    var icon: String {
        switch self {
        case .full:
            return "list.bullet"
        case .upNext:
            return "forward.fill"
        }
    }
}
