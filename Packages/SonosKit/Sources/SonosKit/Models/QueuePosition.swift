public enum QueuePosition: String, Codable, CaseIterable, Identifiable {
    case now
    case next
    case front
    case end
    case replace
    
    public var id: String { self.rawValue }
    
    /// A user-friendly title describing the queue position.
    public var title: String {
        switch self {
        case .front:
            return "Add to Front"
        case .end:
            return "Add to End"
        case .next:
            return "Play Next"
        case .now:
            return "Play Now"
        case .replace:
            return "Replace Queue"
        }
    }
    
    /// A user-friendly title describing the queue position.
    public var shortTitle: String {
        switch self {
        case .front:
            return "Front"
        case .end:
            return "Last"
        case .next:
            return "Next"
        case .now:
            return "Now"
        case .replace:
            return "Replace"
        }
    }
    
    /// A user-friendly title describing the queue position.
    public var symbol: String {
        switch self {
        case .front:
            return "text.insert"
        case .end:
            return "text.append"
        case .next:
            return "forward.end.fill"
        case .now:
            return "play.fill"
        case .replace:
            return "text.badge.xmark"
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
