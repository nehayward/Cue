import Foundation

public struct SpotifyTrack: Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let artistId: String
    public let album: String
    public let albumId: String
    public let duration: Int
    public let albumArtURI: String
    public let isExplicit: Bool
    public let canPlay: Bool
    public let canSkip: Bool
    public let canAddToFavorites: Bool
    
    public var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    public var trackIdOnly: String {
        return id.replacingOccurrences(of: "spotify:track:", with: "")
    }
}

public struct SpotifyMetadataResponse {
    public let tracks: [SpotifyTrack]
    public let index: Int
    public let count: Int
    public let total: Int
}

public struct SpotifyPlaylist: Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    public let albumArtURI: String
    public let canPlay: Bool
    public let canAddToFavorites: Bool
    
    public var IdOnly: String {
        return id.replacingOccurrences(of: "spotify:playlist:", with: "")
    }
}

public struct SpotifyPlaylistResponse {
    public let playlists: [SpotifyPlaylist]
    public let index: Int
    public let count: Int
    public let total: Int
}

public struct SpotifyAlbum: Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let artistId: String
    public let albumArtURI: String
    public let canPlay: Bool
    public let canEnumerate: Bool
    
    public var albumIdOnly: String {
        return id.replacingOccurrences(of: "spotify:album:", with: "")
    }
}

public struct SpotifyAlbumResponse {
    public let albums: [SpotifyAlbum]
    public let index: Int
    public let count: Int
    public let total: Int
}

public struct SpotifyAlbumTrack {
    public let id: String
    public let title: String
    public let artist: String
    public let artistId: String
    public let album: String
    public let albumId: String
    public let duration: Int
    public let albumArtURI: String
    public let trackNumber: Int
    public let isExplicit: Bool
    public let canPlay: Bool
    public let canSkip: Bool
    public let canAddToFavorites: Bool
    
    public var trackIdOnly: String {
        return id.replacingOccurrences(of: "spotify:track:", with: "")
    }
}

public struct SpotifyAlbumTracksResponse {
    public let tracks: [SpotifyAlbumTrack]
    public let index: Int
    public let count: Int
    public let total: Int
}

public struct SpotifySongDetails: Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let artistId: String
    public let album: String
    public let albumId: String
    public let duration: Int
    public let albumArtURI: String
    public let isExplicit: Bool
    public let canPlay: Bool
    public let canSkip: Bool
    public let canAddToFavorites: Bool
    
    public var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    public var trackIDOnly: String {
        return id.replacingOccurrences(of: "spotify:track:", with: "")
    }
    
    public var albumIdOnly: String {
        return albumId.replacingOccurrences(of: "spotify:album:", with: "")
    }
    
    public var artistIdOnly: String {
        return artistId.replacingOccurrences(of: "spotify:artist:", with: "")
    }
}

public struct SpotifySongDetailsResponse {
    public let songs: [SpotifySongDetails]
    public let index: Int
    public let count: Int
    public let total: Int
}

public struct SpotifyArtist: Identifiable {
    public let id: String
    public let name: String
    public let artist: String?
    public let artistId: String?
    public let itemType: String
    public let displayType: String?
    public let albumArtURI: String
    public let canPlay: Bool
    public let canEnumerate: Bool
    
    public var albumIdOnly: String {
        return id.replacingOccurrences(of: "spotify:album:", with: "")
    }
}

public struct SpotifyArtistResponse {
    public let artists: [SpotifyArtist]
    public let index: Int
    public let count: Int
    public let total: Int
}
