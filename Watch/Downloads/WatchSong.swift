import Foundation
import MusicSearchKit
import WatchSync

/// A song as the watch keeps it: what it shows, and where it comes from on
/// its server. Its stream is built from that when it's fetched, at whatever
/// quality the watch is set to (`stream(at:)`), so changing the quality
/// needs nothing from the server but the songs again.
struct WatchSong: Codable, Hashable, Identifiable, Sendable {
    let source: WatchSource
    /// The id the server's library gives it: a Plex item's Sonos-style id,
    /// a Subsonic id — the same the iPhone uses.
    let contentID: String
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let duration: TimeInterval?
    /// The original file, as MusicSearchKit hands it over.
    let sourceURL: URL
    /// The file's own format (`flac`, `mp3`…).
    let audioCodec: String?

    /// The same on both devices (`WatchKeys`), and the file's name here.
    var key: String { WatchKeys.song(source: source, id: contentID) }
    var id: String { key }

    /// The stream at `quality`: converted to MP3 by the server, or the
    /// original file, with the suffix it arrives under.
    func stream(at quality: WatchDownloadQuality) -> (url: URL, fileExtension: String) {
        let service: ConvertedStream.Service = switch source {
        case .plex: .plex
        case .subsonic: .subsonic
        }
        return ConvertedStream.stream(
            service: service,
            contentID: contentID,
            sourceURL: sourceURL,
            audioCodec: audioCodec,
            format: quality.bitrate == nil ? .original : .mp3,
            bitrate: quality.bitrate ?? StreamTranscoding.defaultBitrate
        )
    }

    /// Plex and Subsonic convert on the server as they send; Plex's
    /// transcoder runs one at a time per client, so its conversions are
    /// fetched one at a time.
    func isPlexConversion(at quality: WatchDownloadQuality) -> Bool {
        source == .plex && quality.bitrate != nil
    }

    /// The pick that puts just this song on the watch.
    var pick: WatchPick {
        WatchPick(source: source, kind: .song, id: contentID, title: title, subtitle: artist, artworkURL: artworkURL)
    }
}
