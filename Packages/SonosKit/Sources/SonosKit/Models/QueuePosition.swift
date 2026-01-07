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

extension QueuePosition {
    /// Determines the appropriate queue position for tap actions based on content type and user preferences
    /// - Parameters:
    ///   - contentType: The type of content being played
    ///   - replaceQueueByDefault: User preference for default play action
    /// - Returns: The appropriate QueuePosition (.now or .replace)
    public static func defaultPosition(
        for contentType: ContentType,
        replaceQueueByDefault: Bool
    ) -> QueuePosition {
        // Playlists always replace queue regardless of setting
        if contentType.isPlaylist {
            return .replace
        }

        // For tracks and albums, respect the user setting
        if [.track, .album, .libraryTrack, .libraryAlbum].contains(contentType) {
            return replaceQueueByDefault ? .replace : .now
        }

        // Default to .now for other content types (radio, favorites, etc.)
        return .now
    }
}
