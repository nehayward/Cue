import Foundation

/// A self-hosted service whose tracks Sonos plays as plain HTTP streams
/// (Subsonic today; Jellyfin/Emby would conform the same way). These services
/// have no Sonos service id: the speaker fetches the URL directly, so it must
/// be deterministic (stable across rebuilds, for queue rows and artwork
/// caching), self-authenticating (a token in the URL — the speaker holds no
/// session), and carry a trailing extension hint (Sonos classifies plain-HTTP
/// queue items by the extension it finds in the URL and rejects
/// extension-less ones with UPnP error 804).
///
/// Conforming a client and adding it to `MusicService.directStreamProvider`
/// turns on the whole playback mechanism: stream-URL track URIs, DIDL
/// metadata with MIME/duration, and container-to-tracks queue expansion.
public protocol DirectStreamProvider {
    /// The stream URL for a track id. `fileExtension` is the file suffix
    /// (e.g. "flac") when known, for the extension hint. `destination` asks
    /// for the stream as the user's transcoding choice (`StreamTranscoding`)
    /// delivers it to a speaker or to this device; `nil` is the original
    /// file, whatever the setting.
    static func streamURL(for id: String, fileExtension: String?, destination: StreamTranscoding.Destination?) -> URL?
}

/// Suffix → MIME lookups shared by direct-stream services (used for the DIDL
/// `protocolInfo` Sonos reads).
public enum AudioMIMEType {
    public static func forSuffix(_ suffix: String?) -> String? {
        switch suffix?.lowercased() ?? "" {
        case "flac": "audio/flac"
        case "mp3": "audio/mpeg"
        case "m4a", "aac", "mp4", "alac": "audio/mp4"
        case "ogg", "oga", "vorbis": "audio/ogg"
        case "opus": "audio/opus"
        case "wav": "audio/wav"
        case "aif", "aiff": "audio/aiff"
        case "wma": "audio/x-ms-wma"
        default: nil
        }
    }
}
