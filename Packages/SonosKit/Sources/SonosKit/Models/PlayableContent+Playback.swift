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
        guard content.type == .track else { return previewURL }
        switch content.service {
        case .subsonic:
            return SubsonicAPI.streamURL(for: id, fileExtension: metadata?.audioCodec, destination: .device) ?? previewURL
        case .plex:
            guard let previewURL, let ratingKey = plexRatingKey else { return previewURL }
            return PlexAPI.playbackStreamURL(from: previewURL, ratingKey: ratingKey)
        default:
            return previewURL
        }
    }

    /// The suffix that stream arrives with — the transcode target, or the
    /// file's own (`audioCodec`) — for the extension a download or cached
    /// copy is saved under, so the player reads it as what it is.
    var playbackFileExtension: String? {
        let original = metadata?.audioCodec?.trimmingCharacters(in: .whitespaces).lowercased()
        guard content.type == .track, [.plex, .subsonic].contains(content.service) else { return original }
        return StreamTranscoding.fileExtension(for: .device, original: original)
    }

    /// A Plex track's `ratingKey`, the last segment of its Sonos-style id
    /// (`<machine>%3A3%3A<ratingKey>`) — the same read `SonosService` uses
    /// to look a queue row back up.
    var plexRatingKey: String? {
        guard content.service == .plex else { return nil }
        let key = (content.id.removingPercentEncoding ?? content.id).components(separatedBy: ":").last ?? ""
        return key.isEmpty ? nil : key
    }
}
