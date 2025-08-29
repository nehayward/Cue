import SwiftUI

public enum SonosSortOption: Int, CaseIterable, Identifiable {
    public var id: Self { self }
    
    case nameAscending
    case nameDescending
    case playing
    
    public var title: String {
        switch self {
        case .nameAscending:
            return "A–Z"
        case .nameDescending:
            return "Z–A"
        case .playing:
            return "Playing"
        }
    }
    
    public var icon: Image {
        switch self {
        case .nameAscending:
            Image("a.down")
        case .nameDescending:
            Image("a.up")
        case .playing:
            Image(systemName: "play.fill")
        }
    }
}
