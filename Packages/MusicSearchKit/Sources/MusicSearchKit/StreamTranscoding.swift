import Foundation

/// How the self-hosted servers (Plex and Subsonic) hand audio over: the
/// original file, or transcoded on the server to MP3 or Opus at a capped
/// bitrate — for a phone on a cellular plan, a slow link home, or a library
/// of FLACs that doesn't need to arrive as FLAC.
///
/// The choice is read from `UserDefaults` statically, like the Subsonic
/// login, so stream URLs can be built from any thread without touching an
/// instance. The keys are mirrored by `Defaults.AppStorageKeys` for the
/// settings UI (`streamTranscodeFormat` / `streamTranscodeBitrate`) — the two
/// must stay in step.
///
/// Where it applies:
/// - Subsonic songs sent to a speaker (`/rest/stream` with `format` and
///   `maxBitRate`), and played or downloaded on this device.
/// - Plex songs played or downloaded on this device (the universal
///   transcoder). Plex on a speaker goes through Plex's own Sonos service,
///   whose quality is set on the Plex server, not here.
public enum StreamTranscoding {
    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case original
        case mp3
        case opus

        public var id: String { rawValue }

        /// The suffix a transcoded stream arrives with, `nil` for the
        /// original file (whose own suffix is the answer).
        public var fileExtension: String? {
            switch self {
            case .original: nil
            case .mp3: "mp3"
            case .opus: "opus"
            }
        }

        /// The codec name both servers take (`format=` on Subsonic,
        /// `audioCodec=` on Plex).
        public var codec: String? {
            switch self {
            case .original: nil
            case .mp3: "mp3"
            case .opus: "opus"
            }
        }

        public var displayName: String {
            switch self {
            case .original: "Original"
            case .mp3: "MP3"
            case .opus: "Opus"
            }
        }
    }

    /// Who is going to play the stream. Sonos players decode MP3, AAC, FLAC,
    /// ALAC, Vorbis, WAV and AIFF but not Opus, so an Opus choice is
    /// delivered as MP3 to a speaker and as Opus to this device.
    public enum Destination: Sendable {
        case speaker
        case device
    }

    public static let formatKey = "dance.cue.streamTranscodeFormat"
    public static let bitrateKey = "dance.cue.streamTranscodeBitrate"

    /// Bitrates on offer, in kbit/s.
    public static let bitrates = [64, 96, 128, 160, 192, 256, 320]
    public static let defaultBitrate = 192

    /// The chosen format; `original` when unset.
    public static var format: Format {
        get {
            UserDefaults.standard.string(forKey: formatKey).flatMap(Format.init(rawValue:)) ?? .original
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: formatKey) }
    }

    /// The bitrate cap in kbit/s for a transcoded stream; the default when
    /// unset or out of range.
    public static var bitrate: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: bitrateKey)
            return bitrates.contains(stored) ? stored : defaultBitrate
        }
        set { UserDefaults.standard.set(newValue, forKey: bitrateKey) }
    }

    public static var isEnabled: Bool { format != .original }

    /// The format actually delivered to `destination`.
    public static func format(for destination: Destination) -> Format {
        switch (format, destination) {
        case (.opus, .speaker): .mp3
        case let (format, _): format
        }
    }

    /// The suffix the stream to `destination` really arrives with — the
    /// transcode target, or the file's own suffix when nothing is transcoded.
    /// Feeds the extension hint Sonos classifies by, the DIDL MIME type, and
    /// the extension a download or cached copy is saved under.
    public static func fileExtension(for destination: Destination, original: String?) -> String? {
        format(for: destination).fileExtension ?? original
    }
}
