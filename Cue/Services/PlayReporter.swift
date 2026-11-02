import Foundation
import MusicSearchKit
import SonosKit

/// Tells Plex and Subsonic servers what this device plays, the way their
/// own apps do — so play counts, Recently Played, the server's Now Playing
/// and anything it forwards on (Navidrome to Last.fm or ListenBrainz) all
/// see songs played in Cue.
///
/// `LocalPlaybackService` feeds it from its poll while the stream player is
/// armed, and ends the play whenever it tears a run down. One play at a
/// time: a new item, or the same song armed again, ends the last one.
///
/// - Subsonic: a "now playing" scrobble when the song starts, and the
///   counting one once `ListenTracker` says enough of it has been heard.
/// - Plex: timeline reports — `playing` every few seconds, `paused` on a
///   pause, `stopped` when the song is left — and the server counts the
///   play itself once the reports carry it past its played threshold.
///
/// Reports are best effort: a server that can't be reached (offline, a
/// downloaded song away from home) simply misses them.
@MainActor
final class PlayReporter {
    static let shared = PlayReporter()

    private init() {}

    /// How often a playing Plex track reports where it is.
    private static let timelineInterval: TimeInterval = 10

    private enum Server {
        case plex(ratingKey: String)
        case subsonic(id: String)
    }

    private struct Play {
        let playID: ObjectIdentifier
        let server: Server
        let startedAt: Date
        var tracker: ListenTracker
        var position: TimeInterval = 0
        var duration: TimeInterval
        var sentNowPlaying = false
        var lastTimeline: (state: PlexAPI.TimelineState, at: Date)?
        /// One of a book's files (`AudiobookPlayer`).
        var isBookFile = false
    }

    private var play: Play?

    /// The player's state on one poll. `playID` names this play of the
    /// item — the player item it is armed as — so a song played again
    /// counts again, while a seek back to the top within one play doesn't.
    func observe(_ item: PlayableContent?, playID: ObjectIdentifier, position: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        if play?.playID != playID {
            end()
            guard let item, let server = Self.server(for: item) else { return }
            play = Play(playID: playID, server: server, startedAt: .now, tracker: ListenTracker(duration: duration), duration: duration,
                        isBookFile: AudiobookPlayer.shared.contains(item))
        }
        guard var current = play else { return }
        current.position = position
        if duration > 0 {
            current.duration = duration
            current.tracker.duration = duration
        }

        var counts = false
        if isPlaying {
            counts = current.tracker.advance(to: position)
        } else {
            current.tracker.pause()
        }

        switch current.server {
        case .subsonic(let id):
            if isPlaying, !current.sentNowPlaying {
                current.sentNowPlaying = true
                Task { await SubsonicAPI.shared.scrobble(id: id, submission: false) }
            }
            if counts {
                let startedAt = current.startedAt
                Task { await SubsonicAPI.shared.scrobble(id: id, submission: true, startedAt: startedAt) }
            }
        case .plex(let ratingKey):
            let state: PlexAPI.TimelineState = isPlaying ? .playing : .paused
            let isDue = current.lastTimeline.map {
                $0.state != state || (isPlaying && Date.now.timeIntervalSince($0.at) >= Self.timelineInterval)
            } ?? isPlaying
            if isDue {
                current.lastTimeline = (state, .now)
                Self.sendTimeline(ratingKey: ratingKey, state: state, time: position, duration: current.duration)
            }
        }
        play = current
    }

    /// The play is over — the song was left, or playback came down. Plex
    /// hears where it got to. A book's file left short of its end is
    /// reported paused there, not stopped: Plex counts a file stopped
    /// partway played, which for a book reads as the listener past it
    /// (and, for a book of one file, finished).
    func end() {
        guard let finished = play else { return }
        play = nil
        if case .plex(let ratingKey) = finished.server, finished.lastTimeline != nil {
            let partway = finished.isBookFile && finished.position < finished.duration * Self.playedThreshold
            Self.sendTimeline(ratingKey: ratingKey, state: partway ? .paused : .stopped, time: finished.position, duration: finished.duration)
        }
    }

    /// Lets the play go without telling the server where it got to: a book
    /// whose place another device has moved since (the Apple Watch), where
    /// this device's last spot would take the book back.
    func forget() {
        play = nil
    }

    /// How far into a track Plex counts it played from its reports.
    static let playedThreshold = 0.9

    private static func sendTimeline(ratingKey: String, state: PlexAPI.TimelineState, time: TimeInterval, duration: TimeInterval) {
        Task { await PlexAPI.shared.reportTimeline(ratingKey: ratingKey, state: state, time: time, duration: duration) }
    }

    /// Which server, if any, hears about plays of `item`.
    private static func server(for item: PlayableContent) -> Server? {
        guard item.content.type == .track else { return nil }
        switch item.content.service {
        case .plex:
            guard let ratingKey = item.plexRatingKey, !ratingKey.isEmpty else { return nil }
            return .plex(ratingKey: ratingKey)
        case .subsonic:
            guard SubsonicAPI.shared.isConfigured, !item.content.id.isEmpty else { return nil }
            return .subsonic(id: item.content.id)
        default:
            return nil
        }
    }
}
