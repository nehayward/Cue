import Foundation

/// M4A, M4B, ALAC and AAC in an MP4 container: the iTunes-style tags in
/// `moov/udta/meta/ilst`, and the length from `mvhd`. Walks the top-level
/// atoms by size, so a file whose `moov` sits after a large `mdat` is read
/// by seeking past the audio, never through it.
enum MP4TagParser {
    static func parse(_ source: TagByteSource) throws -> AudioTags? {
        var position = 0
        var tags: AudioTags?
        while position + 8 <= source.length {
            let header = ByteView(try source.read(at: position, count: 16))
            guard header.count >= 8 else { break }
            var size = header.u32BE(0)
            var headerLength = 8
            if size == 1 {
                size = header.u64BE(8)
                headerLength = 16
            } else if size == 0 {
                size = source.length - position
            }
            // A size the file can't hold — a corrupt 64-bit size can be
            // anything up to `Int.max` — ends the walk. Compared against
            // what is left rather than added to `position`, which would
            // overflow for such a size.
            guard size >= headerLength, size <= source.length - position else { break }

            if header.matches(4, "moov") {
                let bodySize = size - headerLength
                guard bodySize <= TagReader.regionLimit else { break }
                let body = try source.read(at: position + headerLength, count: bodySize)
                tags = parseMoov(ByteView(body))
                break
            }
            position += size
        }
        return tags
    }

    private static func parseMoov(_ moov: ByteView) -> AudioTags {
        var tags = AudioTags()
        forEachAtom(in: moov) { type, body in
            if type == "mvhd" {
                tags.duration = duration(mvhd: body)
            } else if type == "udta" {
                forEachAtom(in: body) { childType, child in
                    if childType == "meta" { tags.merge(parseMeta(child)) }
                }
            } else if type == "meta" {
                tags.merge(parseMeta(body))
            }
        }
        return tags
    }

    private static func duration(mvhd: ByteView) -> Double? {
        let version = mvhd.u8(0)
        let timescale: Int
        let duration: Int
        if version == 1 {
            timescale = mvhd.u32BE(20)
            duration = mvhd.u64BE(24)
        } else {
            timescale = mvhd.u32BE(12)
            duration = mvhd.u32BE(16)
        }
        guard timescale > 0, duration > 0 else { return nil }
        return Double(duration) / Double(timescale)
    }

    /// `meta` is a full atom — four bytes of version and flags before its
    /// children — in every Apple-written file, and a plain one in a few
    /// others. A zero first word says which.
    private static func parseMeta(_ meta: ByteView) -> AudioTags {
        var tags = AudioTags()
        let children = meta.u32BE(0) == 0 ? ByteView(meta.bytes(4, meta.count - 4)) : meta
        forEachAtom(in: children) { type, body in
            if type == "ilst" { tags.merge(parseItemList(body)) }
        }
        return tags
    }

    private static let copyright: UInt8 = 0xA9

    private static func parseItemList(_ list: ByteView) -> AudioTags {
        var tags = AudioTags()
        forEachAtomRaw(in: list) { type, body in
            guard let payload = firstData(in: body) else { return }
            switch type {
            case [copyright, 0x6E, 0x61, 0x6D]: tags.title = text(payload)                   // ©nam
            case [copyright, 0x41, 0x52, 0x54]: tags.artist = text(payload)                  // ©ART
            case Array("aART".utf8): tags.albumArtist = text(payload)
            case [copyright, 0x61, 0x6C, 0x62]: tags.album = text(payload)                   // ©alb
            case [copyright, 0x67, 0x65, 0x6E]: tags.genre = tags.genre ?? text(payload)     // ©gen
            case Array("gnre".utf8):
                // One more than the ID3 index.
                if tags.genre == nil { tags.genre = ID3Genres.name(ByteView(payload.data).u16BE(0) - 1) }
            case [copyright, 0x64, 0x61, 0x79]: tags.year = TagText.year(in: text(payload))  // ©day
            case Array("trkn".utf8):
                let number = ByteView(payload.data).u16BE(2)
                if number > 0 { tags.trackNumber = number }
            case Array("disk".utf8):
                let number = ByteView(payload.data).u16BE(2)
                if number > 0 { tags.discNumber = number }
            case Array("covr".utf8):
                if payload.type == 13 || payload.type == 14 || payload.type == 0, !payload.data.isEmpty {
                    tags.artwork = tags.artwork ?? payload.data
                }
            case Array("cpil".utf8):
                tags.isCompilation = ByteView(payload.data).u8(0) != 0
            default:
                break
            }
        }
        return tags
    }

    private struct DataPayload {
        var type: Int
        var data: Data
    }

    /// The first `data` child of an item: its type indicator's low three
    /// bytes, then the value after the locale word.
    private static func firstData(in item: ByteView) -> DataPayload? {
        var found: DataPayload?
        forEachAtom(in: item) { type, body in
            guard found == nil, type == "data", body.count >= 8 else { return }
            found = DataPayload(type: body.u32BE(0) & 0x00FF_FFFF, data: body.bytes(8, body.count - 8))
        }
        return found
    }

    private static func text(_ payload: DataPayload) -> String? {
        switch payload.type {
        case 2: return TagText.string(payload.data, encoding: .utf16BigEndian)
        default: return TagText.string(payload.data, encoding: .utf8)
        }
    }

    private static func forEachAtom(in view: ByteView, _ body: (String, ByteView) -> Void) {
        forEachAtomRaw(in: view) { type, child in
            body(String(decoding: type, as: UTF8.self), child)
        }
    }

    private static func forEachAtomRaw(in view: ByteView, _ body: ([UInt8], ByteView) -> Void) {
        var position = 0
        while position + 8 <= view.count {
            var size = view.u32BE(position)
            var headerLength = 8
            if size == 1 {
                size = view.u64BE(position + 8)
                headerLength = 16
            } else if size == 0 {
                size = view.count - position
            }
            // Against what is left, not `position + size`: a corrupt 64-bit
            // size can be up to `Int.max`, and the sum would overflow.
            guard size >= headerLength, size <= view.count - position else { break }
            let type = Array(view.bytes(position + 4, 4))
            body(type, ByteView(view.bytes(position + headerLength, size - headerLength)))
            position += size
        }
    }
}
