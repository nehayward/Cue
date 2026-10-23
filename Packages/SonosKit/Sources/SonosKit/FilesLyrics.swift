import AVFoundation
import Foundation

/// A Files song's lyrics as its files hold them, LRC or plain, for
/// `Lyrics.parse` to read.
enum FilesLyrics {
    /// Sidecars beside the song under its own name, the way Plex reads
    /// them: a `.lrc`, then a `.txt`. Ahead of the tags, since a sidecar is
    /// put there on purpose and is usually the timed copy.
    static let sidecarExtensions = ["lrc", "LRC", "txt", "TXT"]

    /// Beyond this a sidecar isn't lyrics.
    static let sidecarLimit = 1_000_000

    /// A sidecar first, then the song's own tags (ID3 USLT, Vorbis LYRICS,
    /// MP4 ©lyr), then whatever AVFoundation finds that the tag reader
    /// doesn't.
    static func read(at url: URL) async -> String? {
        let base = url.deletingPathExtension()
        for pathExtension in sidecarExtensions {
            if let text = sidecar(at: base.appendingPathExtension(pathExtension)) {
                return text
            }
        }
        if let source = try? FileTagSource(url: url) {
            defer { source.close() }
            if let lyrics = (try? TagReader.read(from: source))?.lyrics {
                return lyrics
            }
        }
        if let lyrics = try? await AVURLAsset(url: url).load(.lyrics) {
            return TagText.clean(lyrics)
        }
        return nil
    }

    static func sidecar(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              !data.isEmpty, data.count <= sidecarLimit else { return nil }
        let view = ByteView(data)
        let text: String?
        if view.matches(0, [0xEF, 0xBB, 0xBF]) {
            text = String(data: data.dropFirst(3), encoding: .utf8)
        } else if view.matches(0, [0xFF, 0xFE]) {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if view.matches(0, [0xFE, 0xFF]) {
            text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        } else {
            // Older LRC files are often Latin-1 rather than UTF-8.
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }
        return TagText.clean(text)
    }
}
