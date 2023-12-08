enum SearchSelection: String, Equatable {
    case spotify
    case apple

    var title: String {
        switch self {
        case .spotify:
            "Spotify"
        case .apple:
            "Apple Music"
        }
    }
}
