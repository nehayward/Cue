import Foundation

/// A playlist read from somewhere else — a Spotify or Apple Music link, or a
/// file — before any of it is matched to a service Cue plays. Only what's
/// needed to find each song again: no ids from the source are kept beyond
/// `ImportedTrack.sourceID`, since nothing here is ever played from there.
public struct ImportedPlaylist: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case spotify
        case appleMusic
        case file

        public var title: String {
            switch self {
            case .spotify: "Spotify"
            case .appleMusic: "Apple Music"
            case .file: "File"
            }
        }
    }

    public var name: String
    public let source: Source
    public let artwork: URL?
    public let tracks: [ImportedTrack]
    /// How many songs the source says it holds, when it says so. More than
    /// `tracks.count` when only part of the list could be read — Spotify's
    /// share page lists the first 100.
    public let totalCount: Int?

    public init(name: String, source: Source, artwork: URL? = nil, tracks: [ImportedTrack], totalCount: Int? = nil) {
        self.name = name
        self.source = source
        self.artwork = artwork
        self.tracks = tracks
        self.totalCount = totalCount
    }

    /// Songs the source holds that couldn't be read, or 0.
    public var unreadCount: Int {
        max(0, (totalCount ?? tracks.count) - tracks.count)
    }
}

/// One song of an imported playlist: what it's called and who it's by, as
/// the source wrote it. `id` is its position, so the same song twice in a
/// playlist stays two rows.
public struct ImportedTrack: Sendable, Hashable, Identifiable {
    public let id: Int
    public let title: String
    /// The performers, lead first. A source that writes them as one string
    /// ("Queen & David Bowie") gives one entry; the matcher copes with both.
    public let artists: [String]
    public let album: String?
    /// Seconds.
    public let duration: TimeInterval?
    public let isrc: String?
    /// The song's id at the source (`spotify:track:…`, an Apple Music id),
    /// for opening it there. Never used to match.
    public let sourceID: String?

    public init(
        id: Int,
        title: String,
        artists: [String],
        album: String? = nil,
        duration: TimeInterval? = nil,
        isrc: String? = nil,
        sourceID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.duration = duration
        self.isrc = isrc
        self.sourceID = sourceID
    }

    /// The performers as one line, the way a row shows them.
    public var artistLine: String {
        artists.joined(separator: ", ")
    }
}
