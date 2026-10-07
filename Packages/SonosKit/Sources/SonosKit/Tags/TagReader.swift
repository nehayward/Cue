import Foundation

/// What a file's own tags say about it. Every field is optional: a reader
/// fills what the format carries and leaves the rest for the folder-layout
/// fallback.
public struct AudioTags: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var genre: String?
    public var year: Int?
    public var trackNumber: Int?
    public var discNumber: Int?
    /// Seconds.
    public var duration: Double?
    /// The embedded front cover, as the bytes of the image file.
    public var artwork: Data?
    public var isCompilation = false

    public init() {}

    public var isEmpty: Bool {
        title == nil && artist == nil && albumArtist == nil && album == nil && genre == nil
            && year == nil && trackNumber == nil && discNumber == nil && duration == nil
            && artwork == nil && !isCompilation
    }

    /// Fills in whatever this has no value for from `other`.
    public mutating func merge(_ other: AudioTags) {
        title = title ?? other.title
        artist = artist ?? other.artist
        albumArtist = albumArtist ?? other.albumArtist
        album = album ?? other.album
        genre = genre ?? other.genre
        year = year ?? other.year
        trackNumber = trackNumber ?? other.trackNumber
        discNumber = discNumber ?? other.discNumber
        duration = duration ?? other.duration
        artwork = artwork ?? other.artwork
        isCompilation = isCompilation || other.isCompilation
    }
}

/// Bytes on demand, so a reader asks for the tag region of a file and
/// nothing else. Over a file that is still in iCloud that is the difference
/// between reading its header and downloading the song.
public protocol TagByteSource {
    /// The whole file's size, whether or not the bytes are here.
    var length: Int { get }
    /// The bytes at `offset`; fewer than `count` only at the end of the file.
    func read(at offset: Int, count: Int) throws -> Data
}

/// A source over bytes already in memory — tests, and tags embedded inside
/// another container.
public struct DataTagSource: TagByteSource {
    public let data: Data

    public init(_ data: Data) { self.data = data }

    public var length: Int { data.count }

    public func read(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, offset < data.count, count > 0 else { return Data() }
        // `count` can be a size read from the file — anything up to
        // `Int.max` — so clamp against the remainder rather than adding.
        let end = count >= data.count - offset ? data.count : offset + count
        return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + end))
    }
}

/// A source over a file, reading each range as it is asked for. On a file
/// system that can fetch part of a cloud file, only those ranges come down.
public final class FileTagSource: TagByteSource {
    private let handle: FileHandle
    public let length: Int

    /// `length` is the file's size when the caller already has it; a
    /// dataless file reports its size without being fetched.
    public init(url: URL, length: Int? = nil) throws {
        handle = try FileHandle(forReadingFrom: url)
        if let length {
            self.length = length
        } else if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            self.length = size
        } else {
            self.length = try Int(handle.seekToEnd())
        }
    }

    public func read(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, offset < length, count > 0 else { return Data() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: min(count, length - offset)) ?? Data()
    }

    public func close() {
        try? handle.close()
    }

    deinit {
        try? handle.close()
    }
}

/// Reads a file's tags by what its first bytes say it is, not what its
/// name says. Every reader asks the source only for the bytes its format
/// keeps the tags in.
public enum TagReader {
    /// A tag region larger than this is not read: it is not a tag region.
    static let regionLimit = 32 * 1024 * 1024

    public static func read(from source: TagByteSource) throws -> AudioTags? {
        let head = ByteView(try source.read(at: 0, count: 12))
        guard head.count >= 4 else { return nil }

        if head.matches(0, "ID3") {
            return try readMP3(source)
        }
        if head.matches(0, "fLaC") {
            return try FLACTagParser.parse(source)
        }
        if head.matches(0, "RIFF"), head.matches(8, "WAVE") {
            return try RIFFTagParser.parseWAV(source)
        }
        if head.matches(0, "FORM"), head.matches(8, "AIFF") || head.matches(8, "AIFC") {
            return try RIFFTagParser.parseAIFF(source)
        }
        if head.matches(4, "ftyp") {
            return try MP4TagParser.parse(source)
        }
        if MP3Duration.looksLikeFrameSync(head) {
            return try readMP3(source)
        }
        return nil
    }

    public static func read(data: Data) -> AudioTags? {
        try? read(from: DataTagSource(data))
    }

    /// An MP3, or a raw AAC stream, which carries the same ID3 tags: ID3v2
    /// at the front, ID3v1 at the back, and the first frame for the length.
    private static func readMP3(_ source: TagByteSource) throws -> AudioTags {
        var tags = AudioTags()
        var audioStart = 0
        if let v2 = try ID3v2Parser.parse(source, at: 0) {
            tags = v2.tags
            audioStart = v2.tagSize
        }
        var hasV1 = false
        if source.length >= 128, let v1 = ID3v1Parser.parse(try source.read(at: source.length - 128, count: 128)) {
            hasV1 = true
            tags.merge(v1)
        }
        if tags.duration == nil {
            tags.duration = MP3Duration.estimate(source, audioStart: audioStart, hasID3v1: hasV1)
        }
        return tags
    }
}

// MARK: - Shared helpers

/// Bounds-safe integer and string reads over a `Data`, by offset from its
/// start whatever its `startIndex` is. Reads past the end give zero, so a
/// truncated tag parses to nothing rather than trapping.
struct ByteView {
    let data: Data

    init(_ data: Data) { self.data = data }

    var count: Int { data.count }

    func u8(_ i: Int) -> Int {
        guard i >= 0, i < data.count else { return 0 }
        return Int(data[data.startIndex + i])
    }

    func u16BE(_ i: Int) -> Int { u8(i) << 8 | u8(i + 1) }
    func u24BE(_ i: Int) -> Int { u16BE(i) << 8 | u8(i + 2) }
    func u32BE(_ i: Int) -> Int { u16BE(i) << 16 | u16BE(i + 2) }
    func u16LE(_ i: Int) -> Int { u8(i + 1) << 8 | u8(i) }
    func u32LE(_ i: Int) -> Int { u16LE(i + 2) << 16 | u16LE(i) }

    /// Clamped to `Int.max` — sizes, never arithmetic.
    func u64BE(_ i: Int) -> Int {
        var value: UInt64 = 0
        for k in 0..<8 { value = value << 8 | UInt64(u8(i + k)) }
        return value > UInt64(Int.max) ? Int.max : Int(value)
    }

    /// ID3's 7-bits-per-byte size.
    func synchsafe32(_ i: Int) -> Int {
        (u8(i) & 0x7F) << 21 | (u8(i + 1) & 0x7F) << 14 | (u8(i + 2) & 0x7F) << 7 | (u8(i + 3) & 0x7F)
    }

    func bytes(_ i: Int, _ n: Int) -> Data {
        guard i >= 0, i < data.count, n > 0 else { return Data() }
        // `n` is often a size the file claims, up to `Int.max` for a 64-bit
        // atom: clamp against what is left rather than adding and overflowing.
        let end = n >= data.count - i ? data.count : i + n
        return data.subdata(in: (data.startIndex + i)..<(data.startIndex + end))
    }

    func matches(_ i: Int, _ ascii: String) -> Bool {
        matches(i, Array(ascii.utf8))
    }

    func matches(_ i: Int, _ raw: [UInt8]) -> Bool {
        guard i >= 0, i + raw.count <= data.count else { return false }
        for (k, byte) in raw.enumerated() where data[data.startIndex + i + k] != byte {
            return false
        }
        return true
    }

    func ascii(_ i: Int, _ n: Int) -> String {
        String(decoding: bytes(i, n), as: UTF8.self)
    }
}

enum TagText {
    /// A string in the given encoding with trailing nulls and whitespace
    /// dropped; nil when nothing readable is left.
    static func string(_ data: Data, encoding: String.Encoding) -> String? {
        var bytes = data
        if [.utf16, .utf16LittleEndian, .utf16BigEndian].contains(encoding) {
            // Whole code units only: a byte at a time took the zero half
            // of a last letter like "d" (64 00) and lost the letter.
            while bytes.count >= 2, bytes[bytes.endIndex - 1] == 0, bytes[bytes.endIndex - 2] == 0 {
                bytes.removeLast(2)
            }
        } else {
            while let last = bytes.last, last == 0 { bytes.removeLast() }
        }
        guard !bytes.isEmpty else { return nil }
        let decoded = String(data: bytes, encoding: encoding)
            ?? String(data: bytes, encoding: .isoLatin1)
        return clean(decoded)
    }

    static func clean(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The first four-digit year in a date string, whatever else it holds.
    static func year(in string: String?) -> Int? {
        guard let string, let match = string.firstMatch(of: #/(?:^|\D)(\d{4})(?!\d)/#) else { return nil }
        let value = Int(match.1) ?? 0
        return (1900...2100).contains(value) ? value : nil
    }

    /// "3/12" and "3" both mean 3.
    static func number(in string: String?) -> Int? {
        guard let string else { return nil }
        let head = string.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let digits = head.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        return value
    }

    /// ID3 genre text: "(17)", "17", "(17)Rock" and "Rock" all mean Rock.
    /// "(RX)" and "(CR)" are remix and cover markers, not genres.
    static func genre(_ string: String?) -> String? {
        guard let string = clean(string) else { return nil }
        if let match = string.firstMatch(of: #/^\((\d+)\)(.*)$/#) {
            let rest = clean(String(match.2))
            if let index = Int(match.1), let name = ID3Genres.name(index) {
                return rest ?? name
            }
            return rest
        }
        if string.allSatisfy(\.isNumber), let index = Int(string), let name = ID3Genres.name(index) {
            return name
        }
        if string == "(RX)" || string == "(CR)" { return nil }
        return string
    }
}
