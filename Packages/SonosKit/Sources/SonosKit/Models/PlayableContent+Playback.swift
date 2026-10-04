import Foundation
import MusicSearchKit

/// The stream this device plays a self-hosted track from, and what arrives.
///
/// `previewURL` is the original file — a stable URL that caching and the
/// download check key off — so it is *not* the place to apply the user's
/// transcoding choice, which can change at any time. These are built fresh
/// from the item at play, download and cache time instead, so a new setting
/// takes effect on the next song rather than the next library sync.
public extension PlayableContent {
    /// The URL this device streams the track from: `previewURL` as
    /// `StreamTranscoding` delivers it to the device, or `previewURL`
    /// itself for services that aren't transcoded (Files, Apple previews).
    var playbackStreamURL: URL? {
        deviceStreamURL(for: .player)
    }

    /// The same stream, opened by `reader`: the playback cache and
    /// downloads fetch under names of their own, so fetching a song never
    /// ends the player's stream of it (see `DeviceStream.Reader`).
    func deviceStreamURL(for reader: DeviceStream.Reader) -> URL? {
        guard content.type == .track, let previewURL else { return previewURL }
        return DeviceStream.url(service: content.service, contentID: content.id, sourceURL: previewURL, audioCodec: metadata?.audioCodec, for: reader)
    }

    /// The suffix that stream arrives with — the transcode target, or the
    /// file's own (`audioCodec`) — for the extension a download or cached
    /// copy is saved under, so the player reads it as what it is.
    var playbackFileExtension: String? {
        guard content.type == .track else { return metadata?.audioCodec?.trimmingCharacters(in: .whitespaces).lowercased() }
        return DeviceStream.fileExtension(service: content.service, audioCodec: metadata?.audioCodec)
    }

    /// A Plex track's `ratingKey`, the last segment of its Sonos-style id
    /// (`<machine>%3A3%3A<ratingKey>`) — the same read `SonosService` uses
    /// to look a queue row back up.
    var plexRatingKey: String? {
        guard content.service == .plex else { return nil }
        return DeviceStream.plexRatingKey(contentID: content.id)
    }
}

/// The same answers from the parts a download manifest keeps (service, id,
/// the original file URL, the file's suffix), so a download retried after
/// the Streaming Quality setting changed is made under the new setting
/// rather than the URL that failed.
public enum DeviceStream {
    /// Who on this device opens a stream. Plex converts as it sends, and a
    /// transcode started under a session (or client) already converting
    /// ends the one before it. The player, the playback cache and downloads
    /// often want the same song at once — skipping past what the cache has
    /// fetched lands the player on a song the cache then asks for too — so
    /// each runs under its own session and client, and none ends another's.
    public enum Reader: Sendable {
        case player
        case cache
        case download

        /// The prefix of the Plex transcode session, before the rating key.
        public var plexSession: String {
            switch self {
            case .player: "cue"
            case .cache: "cue-cache"
            case .download: "cue-download"
            }
        }

        /// The Plex client the transcode runs under.
        public var plexClient: String {
            switch self {
            case .player: "Cue"
            case .cache: "Cue-Cache"
            case .download: "Cue-Download"
            }
        }
    }

    /// Services whose device stream follows `StreamTranscoding`.
    public static func isTranscodable(_ service: MusicService) -> Bool {
        [.plex, .subsonic].contains(service)
    }

    public static func url(service: MusicService, contentID: String, sourceURL: URL, audioCodec: String?, for reader: Reader = .player) -> URL {
        switch service {
        case .subsonic:
            SubsonicAPI.streamURL(for: contentID, fileExtension: audioCodec, destination: .device) ?? sourceURL
        case .plex:
            plexRatingKey(contentID: contentID).map {
                PlexAPI.playbackStreamURL(from: sourceURL, ratingKey: $0, session: reader.plexSession, client: reader.plexClient)
            } ?? sourceURL
        default:
            sourceURL
        }
    }

    public static func fileExtension(service: MusicService, audioCodec: String?) -> String? {
        let original = audioCodec?.trimmingCharacters(in: .whitespaces).lowercased()
        guard isTranscodable(service) else { return original }
        return StreamTranscoding.fileExtension(for: .device, original: original)
    }

    public static func plexRatingKey(contentID: String) -> String? {
        let key = (contentID.removingPercentEncoding ?? contentID).components(separatedBy: ":").last ?? ""
        return key.isEmpty ? nil : key
    }
}
