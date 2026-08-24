enum SearchSelection: String, Equatable {
    case spotify
    case apple
    case library

    var title: String {
        switch self {
        case .spotify:
            "Spotify"
        case .apple:
            "Apple Music"
        case .library:
            "Library"
        }
    }
}
