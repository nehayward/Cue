import Foundation
import Observation

@Observable
public class Track {
    public var name: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var artworkURL: URL? = nil
    public var musicService: MusicService = .apple
    public var duration: TimeInterval = .zero
    public var playbackPosition: TimeInterval = .zero

    public init(name: String, artist: String, album: String, artworkURL: URL? = nil, musicService: MusicService, duration: TimeInterval, playbackPosition: TimeInterval) {
        self.name = name
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.musicService = musicService
        self.duration = duration
        self.playbackPosition = playbackPosition
    }
}


extension Track: Hashable {
    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.name == rhs.name &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.artworkURL == rhs.artworkURL &&
        lhs.musicService == rhs.musicService &&
        lhs.duration == rhs.duration &&
        lhs.playbackPosition == rhs.playbackPosition
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(artist)
        hasher.combine(album)
        hasher.combine(artworkURL)
        hasher.combine(musicService)
        hasher.combine(duration)
        hasher.combine(playbackPosition)
    }
}

public extension Track {
    var timestamp: String {
        let seconds = playbackPosition / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds.truncatingRemainder(dividingBy: 60)

        return String(format: "%01.0f:%02.0f", minutes, remainingSeconds)
    }

    var remainingTimestamp: String {
        let seconds = (duration - playbackPosition) / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%01.0f:%02.0f", minutes, 60 - abs(remainingSeconds))
    }
}
