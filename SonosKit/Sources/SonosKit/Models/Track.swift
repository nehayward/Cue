import Foundation
import Observation

@Observable
public final class Track: Identifiable, Sendable {
    private let queue = DispatchQueue(label: "Room\(UUID().uuidString)")

    public var id: String { trackID }
    public var trackID: String = ""
    public var name: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var artworkURL: URL? = nil
    public var musicService: MusicService = .unknown
    public var duration: TimeInterval = .zero
    public var playbackPosition: TimeInterval = .zero

    public init(trackID: String, name: String, artist: String, album: String, artworkURL: URL? = nil, musicService: MusicService, duration: TimeInterval, playbackPosition: TimeInterval) {
        self.trackID = trackID
        self.name = name
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.musicService = musicService
        self.duration = duration
        self.playbackPosition = playbackPosition
    }

    public func updateTrack(track: Track) {
        queue.sync {
            self.artworkURL = track.artworkURL
        }
    }
}


extension Track: Hashable {
    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.trackID == rhs.trackID &&
        lhs.name == rhs.name
//        lhs.artist == rhs.artist &&
//        lhs.album == rhs.album //&&
//        lhs.musicService == rhs.musicService
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(trackID)
        hasher.combine(name)
        hasher.combine(artist)
        hasher.combine(album)
        hasher.combine(artworkURL)
//        hasher.combine(musicService)
    }
}

public extension Track {
    var timestamp: String {
        let totalSeconds = playbackPosition / 1000
        let hours = Int(totalSeconds / 3600)
        let minutes = Int(totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var remainingTimestamp: String {
        let totalSeconds = (duration - playbackPosition) / 1000
        let hours = Int(totalSeconds / 3600)
        let minutes = Int(totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))


        if hours > 0 {
            return String(format: "-%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "-%02d:%02d", minutes, seconds)
        }
    }

    static var empty = Track(trackID: "",
                             name: "Nothing playing",
                             artist: "",
                             album: "",
                             artworkURL: nil,
                             musicService: .unknown, 
                             duration: .zero,
                             playbackPosition: .zero
    )
}
