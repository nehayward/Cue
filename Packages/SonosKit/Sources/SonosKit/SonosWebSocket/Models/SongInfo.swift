import Foundation

/// Represents information about the currently playing song on a Sonos device
public struct SongInfo: Codable {
    /// The title of the current song
    let title: String
    /// The artist of the current song
    let artist: String
    /// The album name
    let album: String
    /// URL to the album artwork
    let albumArtUri: String?
    /// Duration of the song in seconds
    let duration: Int?
    /// Current playback position in seconds
    let currentTime: Int?
    /// Position in the queue
    let queuePosition: Int?
    /// Total number of items in the queue
    let queueLength: Int?
    /// Current playback state (e.g., "PLAYING", "PAUSED")
    let playbackState: String?
    /// Audio quality information
    let quality: AudioQuality?
} 