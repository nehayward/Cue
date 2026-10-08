import Foundation

/// FLAC: the metadata blocks at the front of the file — STREAMINFO for the
/// length, VORBIS_COMMENT for the tags, PICTURE for the cover.
enum FLACTagParser {
    static func parse(_ source: TagByteSource) throws -> AudioTags? {
        guard ByteView(try source.read(at: 0, count: 4)).matches(0, "fLaC") else { return nil }
        var tags = AudioTags()
        var position = 4
        var pictureType = -1
        while position + 4 <= source.length {
            let header = ByteView(try source.read(at: position, count: 4))
            guard header.count == 4 else { break }
            let isLast = header.u8(0) & 0x80 != 0
            let type = header.u8(0) & 0x7F
            let length = header.u24BE(1)
            position += 4
            switch type {
            case 0:
                streamInfo(ByteView(try source.read(at: position, count: length)), into: &tags)
            case 4:
                comments(ByteView(try source.read(at: position, count: min(length, TagReader.regionLimit))), into: &tags)
            case 6:
                if length <= TagReader.regionLimit,
                   let picture = picture(ByteView(try source.read(at: position, count: length))),
                   picture.type == 3 || pictureType != 3 {
                    tags.artwork = picture.data
                    pictureType = picture.type
                }
            default:
                break
            }
            position += length
            if isLast { break }
        }
        return tags
    }

    private static func streamInfo(_ info: ByteView, into tags: inout AudioTags) {
        guard info.count >= 18 else { return }
        let sampleRate = info.u8(10) << 12 | info.u8(11) << 4 | info.u8(12) >> 4
        let totalSamples = (info.u8(13) & 0x0F) << 32 | info.u8(14) << 24 | info.u8(15) << 16 | info.u8(16) << 8 | info.u8(17)
        guard sampleRate > 0, totalSamples > 0 else { return }
        tags.duration = Double(totalSamples) / Double(sampleRate)
    }

    /// Vorbis comments: a vendor string, then `KEY=value` pairs, all
    /// little-endian length-prefixed UTF-8.
    static func comments(_ block: ByteView, into tags: inout AudioTags) {
        var position = 0
        let vendorLength = block.u32LE(position)
        position += 4 + vendorLength
        let count = block.u32LE(position)
        position += 4
        for _ in 0..<count {
            guard position + 4 <= block.count else { break }
            let length = block.u32LE(position)
            position += 4
            guard length > 0, position + length <= block.count else { break }
            let entry = String(decoding: block.bytes(position, length), as: UTF8.self)
            position += length
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let key = entry[..<equals].uppercased()
            let value = TagText.clean(String(entry[entry.index(after: equals)...]))
            guard let value else { continue }
            switch key {
            case "TITLE": tags.title = tags.title ?? value
            case "ARTIST": tags.artist = tags.artist ?? value
            case "ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST": tags.albumArtist = tags.albumArtist ?? value
            case "ALBUM": tags.album = tags.album ?? value
            case "GENRE": tags.genre = tags.genre ?? value
            case "DATE", "YEAR", "ORIGINALDATE": tags.year = tags.year ?? TagText.year(in: value)
            case "TRACKNUMBER": tags.trackNumber = tags.trackNumber ?? TagText.number(in: value)
            case "DISCNUMBER": tags.discNumber = tags.discNumber ?? TagText.number(in: value)
            case "COMPILATION": tags.isCompilation = tags.isCompilation || value == "1"
            case "LYRICS", "UNSYNCEDLYRICS", "SYNCEDLYRICS": tags.lyrics = tags.lyrics ?? value
            default: break
            }
        }
    }

    private static func picture(_ block: ByteView) -> (type: Int, data: Data)? {
        var position = 0
        let type = block.u32BE(position)
        position += 4
        let mimeLength = block.u32BE(position)
        position += 4 + mimeLength
        let descriptionLength = block.u32BE(position)
        position += 4 + descriptionLength
        position += 16  // width, height, depth, colours
        let dataLength = block.u32BE(position)
        position += 4
        guard dataLength > 0, position + dataLength <= block.count else { return nil }
        return (type, block.bytes(position, dataLength))
    }
}
