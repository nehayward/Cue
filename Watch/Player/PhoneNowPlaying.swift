import Observation
import UIKit
import WatchSync

/// What Cue on the iPhone is playing, for the home screen's card while the
/// watch itself isn't playing: asked for as the app opens and the iPhone
/// comes in reach, then sent by the iPhone as it changes while the app is
/// open. Forgotten when the iPhone goes out of reach. Play, pause and the
/// skips go back to the iPhone (`PhoneConnection.askPhone`), which carries
/// them out as its player's own buttons do.
@MainActor
@Observable
final class PhoneNowPlaying {
    static let shared = PhoneNowPlaying()

    /// The iPhone is in reach (WatchConnectivity's `isReachable`): the home
    /// screen leads with its playback, else with what's on the watch. Taken
    /// as in reach until the session says, as it usually is.
    private(set) var isPhoneInReach = true
    private(set) var current: WatchPhoneNowPlaying?
    /// The cover, decoded once a song.
    private(set) var artwork: UIImage?
    /// When the iPhone was last seen playing, or paused from here: with
    /// both paused, the card is whichever played last.
    private(set) var lastPlayedAt: Date?

    private init() {}

    /// Asks the iPhone what it plays.
    func refresh() {
        PhoneConnection.shared.askPhone(WatchSyncMessage.nowPlayingRequest)
    }

    /// Plays or pauses the iPhone, shown at once; its answer settles it.
    func togglePlayPause() {
        perform(.togglePlayPause)
    }

    /// A press for the iPhone's player: play and pause show at once, a skip
    /// once the iPhone answers with where it went.
    func perform(_ command: WatchPhoneCommand) {
        guard current != nil else { return }
        if command == .togglePlayPause {
            current?.isPlaying.toggle()
            lastPlayedAt = .now
        }
        PhoneConnection.shared.askPhone(WatchSyncMessage.commandRequest(command))
    }

    func apply(_ nowPlaying: WatchPhoneNowPlaying?) {
        if nowPlaying?.isPlaying == true || current?.isPlaying == true {
            lastPlayedAt = .now
        }
        if nowPlaying?.artwork != current?.artwork {
            artwork = nowPlaying?.artwork.flatMap(UIImage.init(data:))
        }
        current = nowPlaying
    }

    /// The iPhone came in reach, so it's asked what it plays, or went out
    /// of it, so what it played is forgotten.
    func reachabilityDidChange(_ isReachable: Bool) {
        isPhoneInReach = isReachable
        if isReachable {
            refresh()
        } else {
            current = nil
            artwork = nil
        }
    }
}
