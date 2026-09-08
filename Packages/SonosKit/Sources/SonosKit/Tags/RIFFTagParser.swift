import Foundation

/// WAV and AIFF: chunked containers whose tags live in a `LIST INFO`
/// (WAV), `NAME`/`AUTH` (AIFF), or an embedded ID3v2 chunk, with the length
/// from the format chunk and the audio chunk's size. The audio chunk is
/// skipped by its size, so a tag chunk after it is reached by seeking.
enum RIFFTagParser {
    static func parseWAV(_ source: TagByteSource) throws -> AudioTags? {
        var tags = AudioTags()
        var byteRate = 0
        var dataBytes = 0
        var position = 12
        while position + 8 <= source.length {
            let header = ByteView(try source.read(at: position, count: 8))
            guard header.count == 8 else { break }
            let id = header.ascii(0, 4)
            var size = header.u32LE(4)
            let start = position + 8
            // A streaming writer leaves the size unfilled; the chunk runs to the end.
            if size > source.length - start { size = source.length - start }

            switch id {
            case "fmt ":
                let fmt = ByteView(try source.read(at: start, count: min(size, 64)))
                byteRate = fmt.u32LE(8)
            case "data":
                dataBytes = size
            case "LIST":
                let list = ByteView(try source.read(at: start, count: min(size, 1024 * 1024)))
                if list.matches(0, "INFO") { info(list, into: &tags) }
            case "id3 ", "ID3 ":
                if size <= TagReader.regionLimit, let embedded = ID3v2Parser.parse(data: try source.read(at: start, count: size)) {
                    tags.merge(embedded)
                }
            default:
                break
            }
            position = start + size + (size & 1)
        }
        if tags.duration == nil, byteRate > 0, dataBytes > 0 {
            tags.duration = Double(dataBytes) / Double(byteRate)
        }
        return tags
    }

    private static func info(_ list: ByteView, into tags: inout AudioTags) {
        var position = 4
        while position + 8 <= list.count {
            let id = list.ascii(position, 4)
            let size = list.u32LE(position + 4)
            let value = TagText.string(list.bytes(position + 8, size), encoding: .utf8)
            switch id {
            case "INAM": tags.title = tags.title ?? value
            case "IART": tags.artist = tags.artist ?? value
            case "IPRD": tags.album = tags.album ?? value
            case "IGNR": tags.genre = tags.genre ?? value
            case "ICRD": tags.year = tags.year ?? TagText.year(in: value)
            case "ITRK", "IPRT": tags.trackNumber = tags.trackNumber ?? TagText.number(in: value)
            default: break
            }
            position += 8 + size + (size & 1)
        }
    }

    static func parseAIFF(_ source: TagByteSource) throws -> AudioTags? {
        var tags = AudioTags()
        var position = 12
        while position + 8 <= source.length {
            let header = ByteView(try source.read(at: position, count: 8))
            guard header.count == 8 else { break }
            let id = header.ascii(0, 4)
            var size = header.u32BE(4)
            let start = position + 8
            if size > source.length - start { size = source.length - start }

            switch id {
            case "COMM":
                let comm = ByteView(try source.read(at: start, count: min(size, 18)))
                let frames = comm.u32BE(2)
                let rate = extended80(comm, at: 8)
                // A corrupt rate can come out infinite, or tiny enough that
                // the division does; a length that isn't a real number is
                // no length at all.
                if frames > 0, rate.isFinite, rate > 0 {
                    let seconds = Double(frames) / rate
                    if seconds.isFinite, seconds > 0 { tags.duration = seconds }
                }
            case "NAME":
                let name = try source.read(at: start, count: min(size, 4096))
                tags.title = tags.title ?? TagText.string(name, encoding: .utf8)
            case "AUTH":
                let author = try source.read(at: start, count: min(size, 4096))
                tags.artist = tags.artist ?? TagText.string(author, encoding: .utf8)
            case "ID3 ", "id3 ":
                if size <= TagReader.regionLimit, let embedded = ID3v2Parser.parse(data: try source.read(at: start, count: size)) {
                    // The ID3 chunk is the richer source; its values win.
                    var merged = embedded
                    merged.merge(tags)
                    tags = merged
                }
            default:
                break
            }
            position = start + size + (size & 1)
        }
        return tags
    }

    /// AIFF's sample rate is an 80-bit IEEE extended float.
    static func extended80(_ view: ByteView, at i: Int) -> Double {
        let exponent = view.u16BE(i) & 0x7FFF
        var mantissa: UInt64 = 0
        for k in 0..<8 { mantissa = mantissa << 8 | UInt64(view.u8(i + 2 + k)) }
        guard exponent != 0 || mantissa != 0 else { return 0 }
        let value = Double(mantissa) * pow(2, Double(exponent - 16383 - 63))
        return view.u8(i) & 0x80 != 0 ? -value : value
    }
}
