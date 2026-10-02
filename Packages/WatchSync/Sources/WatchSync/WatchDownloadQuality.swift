import Foundation

/// How songs come down to the Apple Watch: converted by the server to MP3
/// at a bitrate, or the original file. A watch has a fraction of an
/// iPhone's room, and a lossless library runs 25–40 MB a song. MP3 because
/// it's what every server converts to and the watch's player opens; Opus
/// arrives from Plex and Subsonic in Ogg, which it can't.
///
/// Chosen on the watch, which asks the first time it has music to fetch.
/// Changing it converts what's already there: each song keeps playing from
/// its old file until the new one lands.
public enum WatchDownloadQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case small
    case original

    public var id: String { rawValue }

    /// The MP3 bitrate in kbit/s, or nil for the original file.
    public var bitrate: Int? {
        switch self {
        case .high: 256
        case .medium: 192
        case .small: 128
        case .original: nil
        }
    }

    public var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .small: "Small"
        case .original: "Original"
        }
    }

    /// What it is and roughly what it costs, for a picker row.
    public var detail: String {
        switch self {
        case .high, .medium, .small:
            "MP3 \(bitrate ?? 0) kbps • about \(megabytesPerSong) MB a song"
        case .original:
            "As on your server • lossless is 25–40 MB a song"
        }
    }

    /// A four-minute song at this bitrate, in whole megabytes.
    public var megabytesPerSong: Int {
        guard let bitrate else { return 30 }
        return Int((Double(bitrate) * 1000 / 8 * 240 / 1_000_000).rounded())
    }

    /// What a watch gets until someone chooses.
    public static let recommended = WatchDownloadQuality.high
}
