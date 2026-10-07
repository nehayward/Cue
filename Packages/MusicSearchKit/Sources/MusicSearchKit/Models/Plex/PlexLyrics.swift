import Foundation

/// A track's metadata read only as far as its lyric streams
/// (`streamType` 4): one per set of lyrics the server holds for it, from a
/// sidecar `.lrc` / `.txt` or its lyrics agent (LyricFind, with Plex Pass).
struct PlexLyricStreamsContainer: Decodable {
    let mediaContainer: Container

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    struct Container: Decodable {
        let metadata: [Item]?
        enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
    }

    struct Item: Decodable {
        let media: [Media]?
        enum CodingKeys: String, CodingKey { case media = "Media" }
    }

    struct Media: Decodable {
        let part: [Part]?
        enum CodingKeys: String, CodingKey { case part = "Part" }
    }

    struct Part: Decodable {
        let stream: [PlexLyricStream]?
        enum CodingKeys: String, CodingKey { case stream = "Stream" }
    }

    var lyricStreams: [PlexLyricStream] {
        (mediaContainer.metadata ?? [])
            .flatMap { $0.media ?? [] }
            .flatMap { $0.part ?? [] }
            .flatMap { $0.stream ?? [] }
            .filter { $0.streamType == PlexLyricStream.lyricStreamType && $0.key != nil }
    }
}

struct PlexLyricStream: Decodable {
    static let lyricStreamType = 4

    let streamType: Int?
    /// `/library/streams/<id>`, where the lyrics themselves are.
    let key: String?
    /// "lrc" or "txt".
    let format: String?
    let codec: String?
    /// `com.plexapp.agents.lyricfind`, `com.plexapp.agents.localmedia`, …
    let provider: String?
    let timed: Bool

    enum CodingKeys: String, CodingKey {
        case streamType, key, format, codec, provider, timed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamType = try? container.decode(Int.self, forKey: .streamType)
        key = try? container.decode(String.self, forKey: .key)
        format = try? container.decode(String.self, forKey: .format)
        codec = try? container.decode(String.self, forKey: .codec)
        provider = try? container.decode(String.self, forKey: .provider)
        timed = PlexFlexibleBool.decode(container, .timed)
    }

    /// Timed by Plex's word, or an LRC file, which nearly always is.
    var isLikelyTimed: Bool {
        timed || format?.lowercased() == "lrc" || codec?.lowercased() == "lrc"
    }

    /// Who to credit for the words: the lyrics agent's name, and nobody for
    /// a file of the user's own.
    var credit: String? {
        guard let provider = provider?.lowercased() else { return nil }
        if provider.contains("lyricfind") { return "LyricFind" }
        if provider.contains("musixmatch") { return "Musixmatch" }
        return nil
    }
}

/// What a lyric stream's `key` answers for an agent's lyrics: lines with
/// a start in milliseconds, each made of spans of text. A sidecar file's
/// stream answers with the file itself instead.
struct PlexLyricsContainer: Decodable {
    let mediaContainer: Container

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    struct Container: Decodable {
        let lyrics: [Body]?
        enum CodingKeys: String, CodingKey { case lyrics = "Lyrics" }
    }

    struct Body: Decodable {
        let line: [Line]?
        enum CodingKeys: String, CodingKey { case line = "Line" }
    }

    struct Line: Decodable {
        let startOffset: Double?
        let endOffset: Double?
        let span: [Span]?
        enum CodingKeys: String, CodingKey { case startOffset, endOffset, span = "Span" }

        var text: String { (span ?? []).compactMap(\.text).joined() }

        /// The spans as words, when more than one carries its own start:
        /// LyricFind's timed lyrics come a word or a phrase to a span.
        var words: [Lyrics.Word]? {
            let timed = (span ?? []).compactMap { span -> Lyrics.Word? in
                guard let start = span.startOffset, let text = span.text, !text.isEmpty else { return nil }
                return Lyrics.Word(start: start / 1000, text: text)
            }
            return timed.count > 1 && timed.count == (span ?? []).filter({ $0.text?.isEmpty == false }).count ? timed : nil
        }
    }

    struct Span: Decodable {
        let startOffset: Double?
        let text: String?
    }

    func lyrics(credit: String?) -> Lyrics? {
        for body in mediaContainer.lyrics ?? [] {
            let lines = body.line ?? []
            if lines.contains(where: { $0.startOffset != nil }) {
                var last: TimeInterval = 0
                let timed = lines.map { line -> Lyrics.TimedLine in
                    let start = line.startOffset.map { $0 / 1000 } ?? last
                    last = start
                    return Lyrics.TimedLine(start: start, text: line.text, words: line.words, end: line.endOffset.map { $0 / 1000 })
                }
                if let lyrics = Lyrics.timed(lines: timed, source: .plex, credit: credit), !lyrics.isEmpty {
                    return lyrics
                }
            } else if let lyrics = Lyrics.plain(lines.map(\.text), source: .plex, credit: credit), !lyrics.isEmpty {
                return lyrics
            }
        }
        return nil
    }
}

/// Plex writes flags as `true`, `1` or `"1"` depending on the endpoint.
enum PlexFlexibleBool {
    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Bool {
        if let value = try? container.decode(Bool.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? container.decode(String.self, forKey: key) { return value == "1" || value.lowercased() == "true" }
        return false
    }
}
