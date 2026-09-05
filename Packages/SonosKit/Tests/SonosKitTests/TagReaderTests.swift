import XCTest
@testable import SonosKit

/// The tag reader against files built byte by byte: ID3v2 in each of its
/// three layouts, ID3v1, MP4 atoms, FLAC blocks, WAV and AIFF chunks — and
/// the length worked out from each.
final class TagReaderTests: XCTestCase {

    // MARK: - Byte builders

    private func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private func be32(_ v: Int) -> [UInt8] { be16(v >> 16) + be16(v & 0xFFFF) }
    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    private func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16) }
    private func synchsafe(_ v: Int) -> [UInt8] {
        [UInt8(v >> 21 & 0x7F), UInt8(v >> 14 & 0x7F), UInt8(v >> 7 & 0x7F), UInt8(v & 0x7F)]
    }
    private func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }
    private func latin1(_ s: String) -> [UInt8] { Array(s.data(using: .isoLatin1)!) }

    private let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00]

    /// A 2.3 or 2.4 frame; `body` already carries its encoding byte.
    private func frame(_ id: String, _ body: [UInt8], major: Int = 3, flags: Int = 0) -> [UInt8] {
        ascii(id) + (major == 4 ? synchsafe(body.count) : be32(body.count)) + be16(flags) + body
    }

    private func textFrame(_ id: String, _ text: String, major: Int = 3) -> [UInt8] {
        frame(id, [3] + ascii(text), major: major)
    }

    private func tag(major: Int, flags: UInt8 = 0, body: [UInt8]) -> [UInt8] {
        ascii("ID3") + [UInt8(major), 0, flags] + synchsafe(body.count) + body
    }

    /// MPEG-1 Layer III, 128 kbit/s, 44.1 kHz, stereo: 417-byte frames.
    private func mp3Frames(_ count: Int, firstFrameExtra: [UInt8] = []) -> [UInt8] {
        var frames: [UInt8] = []
        for index in 0..<count {
            var frame: [UInt8] = [0xFF, 0xFB, 0x90, 0x00] + Array(repeating: 0, count: 413)
            if index == 0, !firstFrameExtra.isEmpty {
                frame.replaceSubrange(36..<(36 + firstFrameExtra.count), with: firstFrameExtra)
            }
            frames += frame
        }
        return frames
    }

    private func id3v1(title: String, artist: String, album: String, year: String, track: Int?, genre: UInt8) -> [UInt8] {
        func field(_ s: String, _ n: Int) -> [UInt8] { Array((latin1(s) + Array(repeating: 0, count: n)).prefix(n)) }
        var comment = Array(repeating: UInt8(0), count: 30)
        if let track { comment[29] = UInt8(track) }
        return ascii("TAG") + field(title, 30) + field(artist, 30) + field(album, 30) + field(year, 4) + comment + [genre]
    }

    private func read(_ bytes: [UInt8]) throws -> AudioTags {
        try XCTUnwrap(try TagReader.read(from: DataTagSource(Data(bytes))))
    }

    // MARK: - ID3v2.3

    func testID3v23TextFramesInEveryEncodingPictureAndCBRDuration() throws {
        let utf16Artist: [UInt8] = [1, 0xFF, 0xFE] + Array("Radiohead".utf16).flatMap { le16(Int($0)) }
        let utf16BEAlbumArtist: [UInt8] = [2] + Array("Radio Head".utf16).flatMap { be16(Int($0)) }
        let apic: [UInt8] = [0] + ascii("image/jpeg") + [0] + [3] + ascii("Cover") + [0] + jpeg
        let body = frame("TIT2", [0] + latin1("Karma Police"))
            + frame("TPE1", utf16Artist)
            + frame("TPE2", utf16BEAlbumArtist)
            + frame("TALB", [0] + latin1("OK Computer"))
            + frame("TCON", [0] + latin1("(17)"))
            + frame("TYER", [0] + latin1("1997"))
            + frame("TRCK", [0] + latin1("3/12"))
            + frame("TPOS", [0] + latin1("1/2"))
            + frame("TCMP", [0] + latin1("1"))
            + frame("APIC", apic)
            + Array(repeating: 0, count: 64)  // padding
        let file = tag(major: 3, body: body) + mp3Frames(100) + id3v1(title: "Old Name", artist: "", album: "", year: "1990", track: 9, genre: 20)

        let tags = try read(file)

        XCTAssertEqual(tags.title, "Karma Police")
        XCTAssertEqual(tags.artist, "Radiohead")
        XCTAssertEqual(tags.albumArtist, "Radio Head")
        XCTAssertEqual(tags.album, "OK Computer")
        XCTAssertEqual(tags.genre, "Rock")
        XCTAssertEqual(tags.year, 1997)
        XCTAssertEqual(tags.trackNumber, 3)
        XCTAssertEqual(tags.discNumber, 1)
        XCTAssertTrue(tags.isCompilation)
        XCTAssertEqual(tags.artwork, Data(jpeg))
        // 100 frames × 417 bytes at 128 kbit/s; the v1 tag is not audio.
        XCTAssertEqual(try XCTUnwrap(tags.duration), 100 * 417 * 8 / 128_000, accuracy: 0.001)
    }

    func testID3v23WholeTagUnsynchronisationAndExtendedHeader() throws {
        // "ÿ" is 0xFF in Latin-1; unsynchronised it is written FF 00.
        let extended: [UInt8] = be32(6) + Array(repeating: 0, count: 6)
        let real = frame("TIT2", [0] + latin1("ÿes"))
        // Sizes describe the real bytes; the whole body is then unsynchronised.
        var unsynced: [UInt8] = []
        for byte in extended + real {
            unsynced.append(byte)
            if byte == 0xFF { unsynced.append(0) }
        }
        let tags = try read(tag(major: 3, flags: 0x80 | 0x40, body: unsynced) + mp3Frames(2))
        XCTAssertEqual(tags.title, "ÿes")
    }

    // MARK: - ID3v2.4

    func testID3v24SynchsafeSizesUTF8AndPerFrameUnsynchronisation() throws {
        let body = textFrame("TIT2", "Café", major: 4)
            + textFrame("TDRC", "2004-03-09", major: 4)
            + frame("TPE1", [0, 0xFF, 0x00], major: 4, flags: 0x0002)  // "ÿ", unsynchronised
            + frame("TALB", [0, 0, 0, 3] + [3] + ascii("Album"), major: 4, flags: 0x0001)  // data length indicator
            + textFrame("TCON", "Custom Genre", major: 4)
            + textFrame("TLEN", "90000", major: 4)
        let tags = try read(tag(major: 4, flags: 0x10, body: body) + Array(repeating: 0, count: 10) + mp3Frames(2))
        XCTAssertEqual(tags.title, "Café")
        XCTAssertEqual(tags.year, 2004)
        XCTAssertEqual(tags.artist, "ÿ")
        XCTAssertEqual(tags.album, "Album")
        XCTAssertEqual(tags.genre, "Custom Genre")
        XCTAssertEqual(tags.duration, 90, "TLEN beats an estimate")
    }

    func testID3v24MultipleValuesTakeTheFirst() throws {
        let body = frame("TPE1", [3] + ascii("First") + [0] + ascii("Second"), major: 4)
        XCTAssertEqual(try read(tag(major: 4, body: body) + mp3Frames(1)).artist, "First")
    }

    // MARK: - ID3v2.2

    func testID3v22ThreeByteFrames() throws {
        func frame22(_ id: String, _ body: [UInt8]) -> [UInt8] {
            ascii(id) + [UInt8(body.count >> 16 & 0xFF), UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)] + body
        }
        let body = frame22("TT2", [0] + latin1("Old Title"))
            + frame22("TP1", [0] + latin1("Old Artist"))
            + frame22("TAL", [0] + latin1("Old Album"))
            + frame22("TRK", [0] + latin1("7"))
            + frame22("TYE", [0] + latin1("1989"))
            + frame22("PIC", [0] + ascii("JPG") + [3] + [0] + jpeg)
        let tags = try read(tag(major: 2, body: body) + mp3Frames(3))
        XCTAssertEqual(tags.title, "Old Title")
        XCTAssertEqual(tags.artist, "Old Artist")
        XCTAssertEqual(tags.album, "Old Album")
        XCTAssertEqual(tags.trackNumber, 7)
        XCTAssertEqual(tags.year, 1989)
        XCTAssertEqual(tags.artwork, Data(jpeg))
    }

    // MARK: - ID3v1 and duration

    func testID3v1OnlyAndXingFrameCount() throws {
        let xing: [UInt8] = ascii("Xing") + be32(1) + be32(1000)
        let file = mp3Frames(5, firstFrameExtra: xing) + id3v1(title: "Old Song", artist: "Someone", album: "LP", year: "1985", track: 7, genre: 17)
        let tags = try read(file)
        XCTAssertEqual(tags.title, "Old Song")
        XCTAssertEqual(tags.artist, "Someone")
        XCTAssertEqual(tags.album, "LP")
        XCTAssertEqual(tags.year, 1985)
        XCTAssertEqual(tags.trackNumber, 7)
        XCTAssertEqual(tags.genre, "Rock")
        XCTAssertEqual(try XCTUnwrap(tags.duration), 1000 * 1152 / 44100, accuracy: 0.001)
    }

    func testVBRIFrameCount() throws {
        var vbri: [UInt8] = ascii("VBRI") + be16(1) + be16(0) + be16(0) + be32(0) + be32(500)
        vbri = Array(repeating: 0, count: 32) + vbri  // VBRI sits 32 bytes past the header
        var file = mp3Frames(3)
        file.replaceSubrange(4..<(4 + vbri.count), with: vbri)
        XCTAssertEqual(try XCTUnwrap(try read(file).duration), 500 * 1152 / 44100, accuracy: 0.001)
    }

    func testJunkBeforeTheFirstFrameIsSkipped() throws {
        let file = tag(major: 3, body: textFrame("TIT2", "T")) + Array(repeating: 0xAB, count: 300) + mp3Frames(10)
        XCTAssertEqual(try XCTUnwrap(try read(file).duration), 10 * 417 * 8 / 128_000, accuracy: 0.001)
    }

    // MARK: - MP4

    private func atom(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(8 + payload.count) + ascii(type) + payload
    }

    private func atom(_ type: [UInt8], _ payload: [UInt8]) -> [UInt8] {
        be32(8 + payload.count) + type + payload
    }

    private func dataAtom(type: Int, _ payload: [UInt8]) -> [UInt8] {
        atom("data", be32(type) + be32(0) + payload)
    }

    private func mp4(moovFirst: Bool, mdatSize: Int = 5000, wideMdat: Bool = false) -> [UInt8] {
        let c: UInt8 = 0xA9
        let ilst = atom([c] + ascii("nam"), dataAtom(type: 1, ascii("Song")))
            + atom([c] + ascii("ART"), dataAtom(type: 1, ascii("Artist")))
            + atom("aART", dataAtom(type: 1, ascii("Album Artist")))
            + atom([c] + ascii("alb"), dataAtom(type: 1, ascii("Album")))
            + atom("gnre", dataAtom(type: 0, be16(18)))
            + atom([c] + ascii("day"), dataAtom(type: 1, ascii("2004-03-09")))
            + atom("trkn", dataAtom(type: 0, [0, 0, 0, 3, 0, 12, 0, 0]))
            + atom("disk", dataAtom(type: 0, [0, 0, 0, 2, 0, 2]))
            + atom("covr", dataAtom(type: 13, jpeg))
            + atom("cpil", dataAtom(type: 21, [1]))
        let meta = atom("meta", be32(0) + atom("hdlr", Array(repeating: 0, count: 24)) + atom("ilst", ilst))
        let mvhd = atom("mvhd", [0, 0, 0, 0] + be32(0) + be32(0) + be32(44100) + be32(441_000) + Array(repeating: 0, count: 80))
        let moov = atom("moov", mvhd + atom("udta", meta))
        let ftyp = atom("ftyp", ascii("M4A ") + be32(0) + ascii("M4A mp42isom"))
        let mdat: [UInt8]
        if wideMdat {
            mdat = be32(1) + ascii("mdat") + be32(0) + be32(16 + mdatSize) + Array(repeating: 0, count: mdatSize)
        } else {
            mdat = atom("mdat", Array(repeating: 0, count: mdatSize))
        }
        return moovFirst ? ftyp + moov + mdat : ftyp + mdat + moov
    }

    private func assertMP4(_ tags: AudioTags) {
        XCTAssertEqual(tags.title, "Song")
        XCTAssertEqual(tags.artist, "Artist")
        XCTAssertEqual(tags.albumArtist, "Album Artist")
        XCTAssertEqual(tags.album, "Album")
        XCTAssertEqual(tags.genre, "Rock", "gnre is one more than the ID3 index")
        XCTAssertEqual(tags.year, 2004)
        XCTAssertEqual(tags.trackNumber, 3)
        XCTAssertEqual(tags.discNumber, 2)
        XCTAssertEqual(tags.artwork, Data(jpeg))
        XCTAssertTrue(tags.isCompilation)
        XCTAssertEqual(tags.duration, 10)
    }

    func testMP4FastStart() throws {
        assertMP4(try read(mp4(moovFirst: true)))
    }

    func testMP4MoovAfterMdatIsReachedBySeeking() throws {
        assertMP4(try read(mp4(moovFirst: false)))
    }

    func testMP4SixtyFourBitAtomSize() throws {
        assertMP4(try read(mp4(moovFirst: false, wideMdat: true)))
    }

    func testMP4AtomSizesPastTheEndOfTheFileDoNotTrap() throws {
        // A 64-bit size of all ones — a corrupt `free` atom — used to be
        // added to the walk position, which overflows.
        let huge = be32(1) + ascii("free") + Array(repeating: UInt8(0xFF), count: 8)
        let file = atom("ftyp", ascii("M4A ")) + huge + atom("moov", [])
        XCTAssertNil(try TagReader.read(from: DataTagSource(Data(file))), "The walk stops at the atom it can't step over")

        // The same inside `moov`, where the children are walked in memory.
        let c: UInt8 = 0xA9
        let ilst = atom([c] + ascii("nam"), dataAtom(type: 1, ascii("Song")))
        let meta = atom("meta", be32(0) + atom("ilst", ilst))
        let corrupt = atom("moov", atom("udta", meta) + be32(1) + ascii("trak") + Array(repeating: UInt8(0xFF), count: 8))
        let tags = try read(atom("ftyp", ascii("M4A ")) + corrupt)
        XCTAssertEqual(tags.title, "Song", "What came before the corrupt atom is kept")

        // A 32-bit size beyond the file, likewise.
        let past = be32(1_000_000) + ascii("free")
        XCTAssertNil(try TagReader.read(from: DataTagSource(Data(atom("ftyp", ascii("M4A ")) + past))))
    }

    func testMP4TextGenreAndVersionOneMovieHeader() throws {
        let c: UInt8 = 0xA9
        let ilst = atom([c] + ascii("gen"), dataAtom(type: 1, ascii("Shoegaze")))
        let meta = atom("meta", be32(0) + atom("ilst", ilst))
        // Version 1: 64-bit times, timescale at 20, duration at 24.
        let mvhd = atom("mvhd", [1, 0, 0, 0] + Array(repeating: 0, count: 16) + be32(1000) + be32(0) + be32(65_500) + Array(repeating: 0, count: 80))
        let file = atom("ftyp", ascii("M4A ")) + atom("moov", mvhd + atom("udta", meta))
        let tags = try read(file)
        XCTAssertEqual(tags.genre, "Shoegaze")
        XCTAssertEqual(tags.duration, 65.5)
    }

    // MARK: - FLAC

    private func flacBlock(type: UInt8, last: Bool, _ payload: [UInt8]) -> [UInt8] {
        [type | (last ? 0x80 : 0)] + [UInt8(payload.count >> 16 & 0xFF), UInt8(payload.count >> 8 & 0xFF), UInt8(payload.count & 0xFF)] + payload
    }

    private func vorbisComments(_ pairs: [String]) -> [UInt8] {
        let vendor = ascii("test")
        var block = le32(vendor.count) + vendor + le32(pairs.count)
        for pair in pairs {
            block += le32(pair.utf8.count) + ascii(pair)
        }
        return block
    }

    func testFLACStreamInfoCommentsAndPicture() throws {
        // 44.1 kHz stereo 16-bit, 441,000 samples: ten seconds.
        let streamInfo: [UInt8] = [0x10, 0x00, 0x10, 0x00, 0, 0, 0, 0, 0, 0, 0x0A, 0xC4, 0x42, 0xF0, 0x00, 0x06, 0xBA, 0xA8] + Array(repeating: 0, count: 16)
        let comments = vorbisComments([
            "TITLE=Everything In Its Right Place", "ARTIST=Radiohead", "ALBUM ARTIST=Radiohead", "ALBUM=Kid A",
            "GENRE=Electronic", "DATE=2000-10-02", "TRACKNUMBER=1/10", "DISCNUMBER=1", "COMPILATION=0",
        ])
        let mime = ascii("image/jpeg")
        let picture = be32(3) + be32(mime.count) + mime + be32(0) + be32(0) + be32(0) + be32(0) + be32(0) + be32(jpeg.count) + jpeg
        let file = ascii("fLaC")
            + flacBlock(type: 0, last: false, streamInfo)
            + flacBlock(type: 4, last: false, comments)
            + flacBlock(type: 6, last: true, picture)
            + Array(repeating: 0xFF, count: 100)

        let tags = try read(file)
        XCTAssertEqual(tags.title, "Everything In Its Right Place")
        XCTAssertEqual(tags.artist, "Radiohead")
        XCTAssertEqual(tags.albumArtist, "Radiohead")
        XCTAssertEqual(tags.album, "Kid A")
        XCTAssertEqual(tags.genre, "Electronic")
        XCTAssertEqual(tags.year, 2000)
        XCTAssertEqual(tags.trackNumber, 1)
        XCTAssertEqual(tags.discNumber, 1)
        XCTAssertFalse(tags.isCompilation)
        XCTAssertEqual(tags.artwork, Data(jpeg))
        XCTAssertEqual(tags.duration, 10)
    }

    // MARK: - WAV

    private func chunk(_ id: String, _ payload: [UInt8], bigEndian: Bool = false) -> [UInt8] {
        let size = bigEndian ? be32(payload.count) : le32(payload.count)
        return ascii(id) + size + payload + (payload.count % 2 == 1 ? [0] : [])
    }

    func testWAVInfoListFormatAndEmbeddedID3() throws {
        let fmt = le16(1) + le16(2) + le32(44100) + le32(176_400) + le16(4) + le16(16)
        let info = ascii("INFO")
            + chunk("INAM", ascii("Wave Title") + [0])
            + chunk("IART", ascii("Wave Artist") + [0])
            + chunk("IPRD", ascii("Wave Album") + [0])
            + chunk("IGNR", ascii("Ambient") + [0])
            + chunk("ICRD", ascii("2011-01-01") + [0])
            + chunk("ITRK", ascii("4") + [0])
        let id3 = tag(major: 3, body: textFrame("TPE2", "Wave Album Artist"))
        let body = ascii("WAVE")
            + chunk("fmt ", fmt)
            + chunk("data", Array(repeating: 0, count: 176_400))
            + chunk("LIST", info)
            + chunk("id3 ", id3)
        let file = ascii("RIFF") + le32(body.count) + body

        let tags = try read(file)
        XCTAssertEqual(tags.title, "Wave Title")
        XCTAssertEqual(tags.artist, "Wave Artist")
        XCTAssertEqual(tags.albumArtist, "Wave Album Artist")
        XCTAssertEqual(tags.album, "Wave Album")
        XCTAssertEqual(tags.genre, "Ambient")
        XCTAssertEqual(tags.year, 2011)
        XCTAssertEqual(tags.trackNumber, 4)
        XCTAssertEqual(tags.duration, 1)
    }

    // MARK: - AIFF

    func testAIFFCommonNameAuthorAndID3() throws {
        // 44,100 frames at 44,100 Hz (0x400E AC44 0000 0000 0000): one second.
        let comm = be16(2) + be32(44100) + be16(16) + [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]
        let id3 = tag(major: 3, body: textFrame("TIT2", "Tag Title"))
        let body = ascii("AIFF")
            + chunk("COMM", comm, bigEndian: true)
            + chunk("NAME", ascii("Aiff Title"), bigEndian: true)
            + chunk("AUTH", ascii("Aiff Artist"), bigEndian: true)
            + chunk("SSND", Array(repeating: 0, count: 1000), bigEndian: true)
            + chunk("ID3 ", id3, bigEndian: true)
        let file = ascii("FORM") + be32(body.count) + body

        let tags = try read(file)
        XCTAssertEqual(tags.title, "Tag Title", "The ID3 chunk wins over NAME")
        XCTAssertEqual(tags.artist, "Aiff Artist", "AUTH stands where the ID3 chunk is silent")
        XCTAssertEqual(tags.duration, 1)
    }

    func testAIFFCorruptSampleRateLeavesTheDurationOut() throws {
        func aiff(rate: [UInt8]) -> [UInt8] {
            let comm = be16(2) + be32(44100) + be16(16) + rate
            let body = ascii("AIFF") + chunk("COMM", comm, bigEndian: true) + chunk("NAME", ascii("Title"), bigEndian: true)
            return ascii("FORM") + be32(body.count) + body
        }
        // An exponent of all ones is infinity.
        let infinite = try read(aiff(rate: [0x7F, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(infinite.title, "Title")
        XCTAssertNil(infinite.duration)
        // A tiny rate divides the frame count into something astronomical;
        // still a number, so the parser keeps it and the index filters it.
        let tiny = try read(aiff(rate: [0x3F, 0xC0, 0x80, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertNotNil(tiny.duration)
        XCTAssertNil(FilesLibraryService.playableDuration(tiny.duration))
    }

    func testExtended80() {
        XCTAssertEqual(RIFFTagParser.extended80(ByteView(Data([0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0])), at: 0), 44100)
        XCTAssertEqual(RIFFTagParser.extended80(ByteView(Data([0x40, 0x0E, 0xBB, 0x80, 0, 0, 0, 0, 0, 0])), at: 0), 48000)
        XCTAssertEqual(RIFFTagParser.extended80(ByteView(Data(repeating: 0, count: 10)), at: 0), 0)
    }

    // MARK: - Odds and ends

    func testUnknownBytesReadAsNothing() throws {
        XCTAssertNil(try TagReader.read(from: DataTagSource(Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))))
        XCTAssertNil(try TagReader.read(from: DataTagSource(Data())))
    }

    func testTruncatedTagDoesNotTrap() throws {
        let full = tag(major: 3, body: textFrame("TIT2", "Karma Police") + textFrame("TALB", "OK Computer"))
        for cut in stride(from: 0, to: full.count, by: 7) {
            _ = try TagReader.read(from: DataTagSource(Data(full.prefix(cut))))
        }
    }

    func testGenreText() {
        XCTAssertEqual(TagText.genre("(17)"), "Rock")
        XCTAssertEqual(TagText.genre("17"), "Rock")
        XCTAssertEqual(TagText.genre("(17)Rock"), "Rock")
        XCTAssertEqual(TagText.genre("(17)Post-Rock"), "Post-Rock")
        XCTAssertEqual(TagText.genre("Shoegaze"), "Shoegaze")
        XCTAssertNil(TagText.genre("(RX)"))
        XCTAssertNil(TagText.genre("  "))
        XCTAssertEqual(ID3Genres.name(0), "Blues")
        XCTAssertNil(ID3Genres.name(500))
    }

    func testNumberAndYearText() {
        XCTAssertEqual(TagText.number(in: "3/12"), 3)
        XCTAssertEqual(TagText.number(in: " 07 "), 7)
        XCTAssertNil(TagText.number(in: "0"))
        XCTAssertNil(TagText.number(in: "abc"))
        XCTAssertEqual(TagText.year(in: "2004-03-09T00:00:00Z"), 2004)
        XCTAssertNil(TagText.year(in: "20110"))
    }

    func testFileSourceReadsRangesOfARealFile() throws {
        let bytes = tag(major: 3, body: textFrame("TIT2", "On Disk")) + mp3Frames(4)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TagReaderTests-\(UUID().uuidString).mp3")
        try Data(bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let source = try FileTagSource(url: url)
        XCTAssertEqual(source.length, bytes.count)
        XCTAssertEqual(try source.read(at: bytes.count - 4, count: 100).count, 4, "Reads stop at the end of the file")
        let tags = try XCTUnwrap(try TagReader.read(from: source))
        source.close()
        XCTAssertEqual(tags.title, "On Disk")
        XCTAssertEqual(tags, try read(bytes))
    }
}
