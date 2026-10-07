import Foundation

/// ID3v2.2, 2.3 and 2.4 — the tag at the front of an MP3, and inside the
/// `id3` chunk of a WAV or AIFF. Handles the three frame layouts, the four
/// text encodings, unsynchronisation (whole-tag in 2.3, per-frame in 2.4),
/// the extended header, and the front-cover picture.
enum ID3v2Parser {
    struct Result {
        var tags: AudioTags
        /// Bytes from the tag's start to the first byte after it — where
        /// the audio begins.
        var tagSize: Int
    }

    static func parse(_ source: TagByteSource, at offset: Int) throws -> Result? {
        let header = ByteView(try source.read(at: offset, count: 10))
        guard let tag = readHeader(header) else { return nil }
        let footer = tag.major == 4 && tag.flags & 0x10 != 0 ? 10 : 0
        let total = 10 + tag.size + footer
        guard tag.size <= TagReader.regionLimit else {
            return Result(tags: AudioTags(), tagSize: total)
        }
        let body = try source.read(at: offset + 10, count: tag.size)
        return Result(tags: parseBody(body, major: tag.major, flags: tag.flags), tagSize: total)
    }

    /// A whole tag already in memory: an embedded chunk.
    static func parse(data: Data) -> AudioTags? {
        let view = ByteView(data)
        guard let tag = readHeader(view) else { return nil }
        return parseBody(view.bytes(10, tag.size), major: tag.major, flags: tag.flags)
    }

    private static func readHeader(_ header: ByteView) -> (major: Int, flags: Int, size: Int)? {
        guard header.count >= 10, header.matches(0, "ID3") else { return nil }
        let major = header.u8(3)
        guard (2...4).contains(major) else { return nil }
        return (major, header.u8(5), header.synchsafe32(6))
    }

    private static func parseBody(_ raw: Data, major: Int, flags: Int) -> AudioTags {
        var body = raw
        // 2.2 and 2.3 unsynchronise the whole tag; 2.4 marks each frame.
        if major < 4, flags & 0x80 != 0 {
            body = deunsynchronised(body)
        }
        let view = ByteView(body)
        var cursor = 0
        if flags & 0x40 != 0 {
            // Extended header: 2.3's size excludes its own four bytes,
            // 2.4's synchsafe size includes them.
            cursor = major == 4 ? view.synchsafe32(0) : 4 + view.u32BE(0)
        }

        var tags = AudioTags()
        var pictureType = -1
        let headerLength = major == 2 ? 6 : 10

        while cursor + headerLength <= view.count {
            let id: String
            let size: Int
            var frameFlags = 0
            if major == 2 {
                id = view.ascii(cursor, 3)
                size = view.u24BE(cursor + 3)
            } else {
                id = view.ascii(cursor, 4)
                size = major == 4 ? view.synchsafe32(cursor + 4) : view.u32BE(cursor + 4)
                frameFlags = view.u16BE(cursor + 8)
            }
            // Padding, or something that isn't a frame: the tag is over.
            guard id.first != "\0", id.allSatisfy({ $0.isLetter || $0.isNumber }), size > 0 else { break }
            guard cursor + headerLength + size <= view.count else { break }

            var frame = view.bytes(cursor + headerLength, size)
            cursor += headerLength + size

            if major == 3 {
                // Compressed or encrypted frames are beyond a tag reader.
                if frameFlags & 0x00C0 != 0 { continue }
                if frameFlags & 0x0020 != 0 { frame = frame.dropFirst(1) }
            } else if major == 4 {
                if frameFlags & 0x000C != 0 { continue }
                if frameFlags & 0x0040 != 0 { frame = frame.dropFirst(1) }
                if frameFlags & 0x0001 != 0 { frame = frame.dropFirst(4) }
                if frameFlags & 0x0002 != 0 || flags & 0x80 != 0 { frame = deunsynchronised(frame) }
            }

            switch id {
            case "TIT2", "TT2": tags.title = tags.title ?? text(frame).first
            case "TPE1", "TP1": tags.artist = tags.artist ?? text(frame).first
            case "TPE2", "TP2": tags.albumArtist = tags.albumArtist ?? text(frame).first
            case "TALB", "TAL": tags.album = tags.album ?? text(frame).first
            case "TCON", "TCO": tags.genre = tags.genre ?? text(frame).compactMap { TagText.genre($0) }.first
            case "TDRC", "TYER", "TYE": tags.year = tags.year ?? TagText.year(in: text(frame).first)
            case "TDOR", "TORY", "TOR": if tags.year == nil { tags.year = TagText.year(in: text(frame).first) }
            case "TRCK", "TRK": tags.trackNumber = tags.trackNumber ?? TagText.number(in: text(frame).first)
            case "TPOS", "TPA": tags.discNumber = tags.discNumber ?? TagText.number(in: text(frame).first)
            case "TCMP", "TCP": tags.isCompilation = tags.isCompilation || text(frame).first == "1"
            case "TLEN", "TLE":
                if tags.duration == nil, let ms = TagText.number(in: text(frame).first), ms > 0 {
                    tags.duration = Double(ms) / 1000
                }
            case "USLT", "ULT":
                tags.lyrics = tags.lyrics ?? lyrics(frame)
            case "APIC", "PIC":
                if let picture = picture(frame, major: major), picture.type == 3 || pictureType != 3 {
                    tags.artwork = picture.data
                    pictureType = picture.type
                }
            default:
                break
            }
        }
        return tags
    }

    /// FF 00 was written for every FF the tag holds; take the 00 back out.
    static func deunsynchronised(_ data: Data) -> Data {
        var out = Data(capacity: data.count)
        var previousWasFF = false
        for byte in data {
            if previousWasFF, byte == 0 {
                previousWasFF = false
                continue
            }
            out.append(byte)
            previousWasFF = byte == 0xFF
        }
        return out
    }

    // MARK: - Text

    /// A text frame's strings: an encoding byte, then one or more
    /// null-separated values in it.
    static func text(_ frame: Data) -> [String] {
        let view = ByteView(frame)
        guard view.count >= 2 else { return [] }
        let body = view.bytes(1, view.count - 1)
        switch view.u8(0) {
        case 0: return splitNarrow(body).compactMap { TagText.string($0, encoding: .isoLatin1) }
        case 3: return splitNarrow(body).compactMap { TagText.string($0, encoding: .utf8) }
        case 1: return splitWide(body).compactMap { decodeUTF16($0, defaultLittleEndian: true) }
        case 2: return splitWide(body).compactMap { decodeUTF16($0, defaultLittleEndian: false) }
        default: return []
        }
    }

    private static func splitNarrow(_ data: Data) -> [Data] {
        data.split(separator: 0, omittingEmptySubsequences: true).map { Data($0) }
    }

    private static func splitWide(_ data: Data) -> [Data] {
        var pieces: [Data] = []
        var current = Data()
        var i = data.startIndex
        while i + 1 < data.endIndex {
            if data[i] == 0, data[i + 1] == 0 {
                if !current.isEmpty { pieces.append(current) }
                current = Data()
            } else {
                current.append(data[i])
                current.append(data[i + 1])
            }
            i += 2
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    private static func decodeUTF16(_ data: Data, defaultLittleEndian: Bool) -> String? {
        let view = ByteView(data)
        if view.matches(0, [0xFF, 0xFE]) {
            return TagText.string(view.bytes(2, view.count - 2), encoding: .utf16LittleEndian)
        }
        if view.matches(0, [0xFE, 0xFF]) {
            return TagText.string(view.bytes(2, view.count - 2), encoding: .utf16BigEndian)
        }
        return TagText.string(data, encoding: defaultLittleEndian ? .utf16LittleEndian : .utf16BigEndian)
    }

    // MARK: - Lyrics

    /// USLT: an encoding byte, a three-letter language, a description
    /// ended by a null in that encoding, then the words.
    static func lyrics(_ frame: Data) -> String? {
        let view = ByteView(frame)
        guard view.count > 4 else { return nil }
        let encoding = view.u8(0)
        var cursor = 4
        if encoding == 1 || encoding == 2 {
            while cursor + 1 < view.count {
                if view.u8(cursor) == 0, view.u8(cursor + 1) == 0 {
                    cursor += 2
                    break
                }
                cursor += 2
            }
        } else {
            while cursor < view.count {
                let byte = view.u8(cursor)
                cursor += 1
                if byte == 0 { break }
            }
        }
        let body = view.bytes(cursor, view.count - cursor)
        switch encoding {
        case 0: return TagText.string(body, encoding: .isoLatin1)
        case 3: return TagText.string(body, encoding: .utf8)
        case 1: return decodeUTF16(body, defaultLittleEndian: true)
        case 2: return decodeUTF16(body, defaultLittleEndian: false)
        default: return nil
        }
    }

    // MARK: - Pictures

    private static func picture(_ frame: Data, major: Int) -> (type: Int, data: Data)? {
        let view = ByteView(frame)
        guard view.count > 4 else { return nil }
        let encoding = view.u8(0)
        var cursor = 1
        if major == 2 {
            // Three-letter format, no MIME.
            cursor += 3
        } else {
            guard let mimeEnd = frame.dropFirst(1).firstIndex(of: 0) else { return nil }
            let mime = view.ascii(1, mimeEnd - frame.startIndex - 1)
            if mime == "-->" { return nil }
            cursor = mimeEnd - frame.startIndex + 1
        }
        let type = view.u8(cursor)
        cursor += 1
        // The description ends at a null: one byte, or an aligned pair for
        // the UTF-16 encodings.
        if encoding == 1 || encoding == 2 {
            while cursor + 1 < view.count {
                if view.u8(cursor) == 0, view.u8(cursor + 1) == 0 {
                    cursor += 2
                    break
                }
                cursor += 2
            }
        } else {
            while cursor < view.count {
                let byte = view.u8(cursor)
                cursor += 1
                if byte == 0 { break }
            }
        }
        let data = view.bytes(cursor, view.count - cursor)
        guard !data.isEmpty else { return nil }
        return (type, data)
    }
}

/// The 128-byte tag at the very end of an MP3.
enum ID3v1Parser {
    static func parse(_ data: Data) -> AudioTags? {
        let view = ByteView(data)
        guard view.count == 128, view.matches(0, "TAG") else { return nil }
        var tags = AudioTags()
        tags.title = TagText.string(view.bytes(3, 30), encoding: .isoLatin1)
        tags.artist = TagText.string(view.bytes(33, 30), encoding: .isoLatin1)
        tags.album = TagText.string(view.bytes(63, 30), encoding: .isoLatin1)
        tags.year = TagText.year(in: TagText.string(view.bytes(93, 4), encoding: .isoLatin1))
        // ID3v1.1 spends the comment's last two bytes on the track number.
        if view.u8(125) == 0, view.u8(126) != 0 {
            tags.trackNumber = view.u8(126)
        }
        tags.genre = ID3Genres.name(view.u8(127))
        return tags
    }
}
