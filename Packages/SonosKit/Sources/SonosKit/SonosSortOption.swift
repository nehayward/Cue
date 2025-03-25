
public enum SonosSortOption: Int, CaseIterable, Identifiable {
    public var id: Self { self }
    
    case nameAscending
    case nameDescending
    case playing
    
    public var title: String {
        switch self {
        case .nameAscending:
            return "Name (A-Z)"
        case .nameDescending:
            return "Name (Z-A)"
        case .playing:
            return "Now Playing"
        }
    }
}
