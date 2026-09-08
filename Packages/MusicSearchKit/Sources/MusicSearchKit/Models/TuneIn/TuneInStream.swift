import Foundation

/// One playable stream for a TuneIn station, from `Tune.ashx?render=json`.
/// A station usually offers one; some offer an HLS variant beside a plain
/// MP3 or AAC one.
public struct TuneInStream: Decodable, Sendable, Hashable {
    public let url: URL
    /// "mp3", "aac", "hls", …
    public let mediaType: String?
    public let bitrate: Int?
    /// 0–100, TuneIn's own measure of how often the stream answers.
    public let reliability: Int?

    enum CodingKeys: String, CodingKey {
        case url
        case mediaType = "media_type"
        case bitrate
        case reliability
    }

    public var isHLS: Bool {
        mediaType?.lowercased() == "hls" || url.pathExtension.lowercased() == "m3u8"
    }
}

struct TuneInStreamResponse: Decodable {
    let body: [TuneInStream]
}

extension Array where Element == TuneInStream {
    /// The stream to hand a player: plain MP3/AAC over HLS — every speaker
    /// and `AVPlayer` take those — and among equals, the one TuneIn rates
    /// most reliable, then the higher bitrate.
    public var preferred: TuneInStream? {
        sorted { lhs, rhs in
            if lhs.isHLS != rhs.isHLS { return !lhs.isHLS }
            if (lhs.reliability ?? 0) != (rhs.reliability ?? 0) { return (lhs.reliability ?? 0) > (rhs.reliability ?? 0) }
            return (lhs.bitrate ?? 0) > (rhs.bitrate ?? 0)
        }.first
    }
}
