@testable import MusicSearchKit
import XCTest

final class LyricsTests: XCTestCase {

    // MARK: - LRC

    func testParsesTimedLinesInOrder() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("""
        [ar:Daft Punk]
        [ti:Get Lucky]
        [00:01.50]Like the legend of the phoenix
        [00:05.25]All ends with beginnings
        [01:02.123]What keeps the planet spinning
        """, source: .lrclib))

        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.map(\.text), [
            "Like the legend of the phoenix",
            "All ends with beginnings",
            "What keeps the planet spinning"
        ])
        XCTAssertEqual(lyrics.lines.map { $0.start! }, [1.5, 5.25, 62.123], accuracy: 0.0001)
        XCTAssertEqual(lyrics.lines.map(\.id), [0, 1, 2])
    }

    func testRepeatedLineWithSeveralStamps() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("""
        [00:10.00][00:30.00]Chorus line
        [00:20.00]Verse line
        """, source: .file))

        XCTAssertEqual(lyrics.lines.map(\.text), ["Chorus line", "Verse line", "Chorus line"])
        XCTAssertEqual(lyrics.lines.map { $0.start! }, [10, 20, 30], accuracy: 0.0001)
    }

    func testOffsetMovesLinesSooner() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("""
        [offset:+500]
        [00:02.00]One
        [00:04.00]Two
        """, source: .file))

        XCTAssertEqual(lyrics.lines.map { $0.start! }, [1.5, 3.5], accuracy: 0.0001)
    }

    func testWordStampsAreDropped() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("[00:01.00]<00:01.00>Hello <00:01.50>world", source: .file))
        XCTAssertEqual(lyrics.lines.first?.text, "Hello world")
    }

    func testTimedBreaksCollapseAndTrailingBreaksGo() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("""
        [00:01.00]One
        [00:05.00]
        [00:06.00]
        [00:10.00]Two
        [00:15.00]
        """, source: .file))

        XCTAssertEqual(lyrics.lines.map(\.text), ["One", "", "Two"])
    }

    func testPlainTextKeepsOneBreakBetweenVerses() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("\r\n[Chorus]\r\nFirst line\r\n\r\n\r\nSecond verse\r\n\r\n", source: .subsonic))

        XCTAssertFalse(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.map(\.text), ["[Chorus]", "First line", "", "Second verse"])
        XCTAssertNil(lyrics.lineIndex(at: 10))
    }

    func testNoWordsIsNil() {
        XCTAssertNil(Lyrics.parse("", source: .file))
        XCTAssertNil(Lyrics.parse("[ar:Someone]\n[ti:Something]\n", source: .file))
        XCTAssertNil(Lyrics.parse("[00:01.00]\n[00:02.00]  ", source: .file))
    }

    func testTimestampForms() {
        XCTAssertEqual(Lyrics.timestamp("01:02"), 62)
        XCTAssertEqual(Lyrics.timestamp("01:02.5")!, 62.5, accuracy: 0.0001)
        XCTAssertEqual(Lyrics.timestamp("01:02.50")!, 62.5, accuracy: 0.0001)
        XCTAssertEqual(Lyrics.timestamp("01:02:50")!, 62.5, accuracy: 0.0001)
        XCTAssertEqual(Lyrics.timestamp("100:00.000"), 6000)
        XCTAssertNil(Lyrics.timestamp("ar:Someone"))
        XCTAssertNil(Lyrics.timestamp("Chorus"))
    }

    func testLineIndexFollowsPosition() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("""
        [00:05.00]One
        [00:10.00]Two
        [00:15.00]Three
        """, source: .file))

        XCTAssertNil(lyrics.lineIndex(at: 0))
        XCTAssertNil(lyrics.lineIndex(at: 4.99))
        XCTAssertEqual(lyrics.lineIndex(at: 5), 0)
        XCTAssertEqual(lyrics.lineIndex(at: 12), 1)
        XCTAssertEqual(lyrics.lineIndex(at: 15), 2)
        XCTAssertEqual(lyrics.lineIndex(at: 500), 2)
    }

    func testRoundTripsThroughCodable() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("[00:05.00]One\n[00:10.00]Two", source: .plex, credit: "LyricFind"))
        let decoded = try JSONDecoder().decode(Lyrics.self, from: JSONEncoder().encode(lyrics))
        XCTAssertEqual(decoded, lyrics)
    }

    // MARK: - Word timing

    func testEnhancedLRCWords() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse(
            "[00:10.00]<00:10.00>Watch <00:10.50>me <00:11.00>dance<00:12.00>\n[00:13.00]Plain line",
            source: .lrclib
        ))

        XCTAssertTrue(lyrics.isWordTimed)
        let first = lyrics.lines[0]
        XCTAssertEqual(first.text, "Watch me dance")
        XCTAssertEqual(first.words?.map(\.text), ["Watch ", "me ", "dance"])
        XCTAssertEqual(first.words?.map(\.start) ?? [], [10, 10.5, 11], accuracy: 0.0001)
        XCTAssertEqual(first.end, 12)
        XCTAssertNil(lyrics.lines[1].words)
    }

    func testWordStampsShiftWithTheOffset() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("[offset:+1000]\n[00:10.00]<00:10.00>One <00:11.00>two", source: .file))
        XCTAssertEqual(lyrics.lines[0].start, 9)
        XCTAssertEqual(lyrics.lines[0].words?.map(\.start) ?? [], [9, 10], accuracy: 0.0001)
    }

    func testProgressThroughTimedWords() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse("[00:10.00]<00:10.00>aaaa<00:11.00>bbbb<00:12.00>", source: .file))
        let line = lyrics.lines[0]
        XCTAssertEqual(line.progress(at: 9, nextStart: nil), 0)
        XCTAssertEqual(line.progress(at: 10.5, nextStart: nil), 0.25, accuracy: 0.0001)
        XCTAssertEqual(line.progress(at: 11, nextStart: nil), 0.5, accuracy: 0.0001)
        XCTAssertEqual(line.progress(at: 11.5, nextStart: nil), 0.75, accuracy: 0.0001)
        XCTAssertEqual(line.progress(at: 30, nextStart: nil), 1)
    }

    func testProgressThroughALineAtASingingPace() throws {
        // 20 characters: 0.075 s each plus 0.3 s is 1.8 s, under the 5 s to
        // the next line, so it's filled well before then.
        let lyrics = try XCTUnwrap(Lyrics.parse("[00:10.00]abcdefghijklmnopqrst\n[00:15.00]next", source: .file))
        let line = lyrics.lines[0]
        XCTAssertEqual(line.progress(at: 10.9, nextStart: 15), 0.5, accuracy: 0.0001)
        XCTAssertEqual(line.progress(at: 12, nextStart: 15), 1)
        // A next line that comes sooner sets the pace instead.
        XCTAssertEqual(line.progress(at: 10.5, nextStart: 11), 0.5, accuracy: 0.0001)
    }

    func testPlexAgentLyricsXML() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer size="1"><Lyrics timed="1" provider="com.plexapp.agents.lyricfind">
          <Line startOffset="1200" endOffset="3000"><Span startOffset="1200" text="Like the legend "/><Span startOffset="2000" text="of the phoenix"/></Line>
          <Line startOffset="4000"/>
          <Line startOffset="6500"><Span text="All ends with beginnings"/></Line>
        </Lyrics></MediaContainer>
        """.utf8)
        let lyrics = try XCTUnwrap(PlexLyricsContainer.lyrics(fromStream: xml, credit: "LyricFind"))
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.map(\.text), ["Like the legend of the phoenix", "", "All ends with beginnings"])
        XCTAssertEqual(lyrics.lines.map { $0.start! }, [1.2, 4, 6.5], accuracy: 0.0001)
        XCTAssertEqual(lyrics.lines.first?.words?.map(\.text), ["Like the legend ", "of the phoenix"])
        XCTAssertEqual(lyrics.credit, "LyricFind")
    }

    func testPlexStreamThatIsAnLRCFile() throws {
        let lyrics = try XCTUnwrap(PlexLyricsContainer.lyrics(fromStream: Data("[00:01.00]One\n[00:02.00]Two".utf8), credit: nil))
        XCTAssertEqual(lyrics.lines.map(\.text), ["One", "Two"])
        XCTAssertEqual(lyrics.source, .plex)
    }

    func testPlexSpansBecomeWords() throws {
        let container = try JSONDecoder().decode(PlexLyricsContainer.self, from: Data("""
        {"MediaContainer": {"Lyrics": [{"Line": [
          {"startOffset": 1000, "endOffset": 2600, "Span": [{"startOffset": 1000, "text": "Hello "}, {"startOffset": 1800, "text": "world"}]}
        ]}]}}
        """.utf8))
        let line = try XCTUnwrap(container.lyrics(credit: nil)?.lines.first)
        XCTAssertEqual(line.words?.map(\.text), ["Hello ", "world"])
        XCTAssertEqual(line.words?.map(\.start) ?? [], [1, 1.8], accuracy: 0.0001)
        XCTAssertEqual(line.end ?? 0, 2.6, accuracy: 0.0001)
    }

    // MARK: - LRCLIB

    func testSearchTitleDropsFeaturesAndRemasters() {
        XCTAssertEqual(LRCLibAPI.searchTitle("Get Lucky (feat. Pharrell Williams & Nile Rodgers)"), "Get Lucky")
        XCTAssertEqual(LRCLibAPI.searchTitle("Here Comes the Sun - Remastered 2009"), "Here Comes the Sun")
        XCTAssertEqual(LRCLibAPI.searchTitle("Heroes [2017 Remaster]"), "Heroes")
        XCTAssertEqual(LRCLibAPI.searchTitle("Live Forever (Live)"), "Live Forever (Live)")
    }

    func testPrimaryArtist() {
        XCTAssertEqual(LRCLibAPI.primaryArtist("Daft Punk feat. Pharrell Williams"), "Daft Punk")
        XCTAssertEqual(LRCLibAPI.primaryArtist("Calvin Harris, Dua Lipa"), "Calvin Harris")
        XCTAssertEqual(LRCLibAPI.primaryArtist("Simon & Garfunkel"), "Simon")
        XCTAssertEqual(LRCLibAPI.primaryArtist("Radiohead"), "Radiohead")
    }

    func testBestMatchKeepsToTheSongsLength() throws {
        let records = try JSONDecoder().decode([LRCLibAPI.Record].self, from: Data("""
        [
          {"id": 1, "trackName": "Get Lucky", "artistName": "Daft Punk", "duration": 248, "plainLyrics": "radio", "syncedLyrics": "[00:01.00]radio"},
          {"id": 2, "trackName": "Get Lucky (Remix)", "artistName": "Daft Punk", "duration": 368, "plainLyrics": "remix", "syncedLyrics": "[00:01.00]remix"},
          {"id": 3, "trackName": "Get Lucky", "artistName": "Daft Punk", "duration": 369, "plainLyrics": "album", "syncedLyrics": null},
          {"id": 4, "trackName": "Get Lucky", "artistName": "Daft Punk", "duration": 367, "plainLyrics": "album", "syncedLyrics": "[00:01.00]album"}
        ]
        """.utf8))

        XCTAssertEqual(LRCLibAPI.best(of: records, title: "Get Lucky (feat. Pharrell Williams)", duration: 369)?.id, 4)
        XCTAssertEqual(LRCLibAPI.best(of: records, title: "Get Lucky", duration: 248)?.id, 1)
        XCTAssertNil(LRCLibAPI.best(of: records, title: "Get Lucky", duration: 100))
    }

    func testInstrumentalRecord() throws {
        let record = try JSONDecoder().decode(LRCLibAPI.Record.self, from: Data("""
        {"id": 9, "trackName": "Interlude", "instrumental": true, "plainLyrics": null, "syncedLyrics": null}
        """.utf8))
        let lyrics = try XCTUnwrap(LRCLibAPI.lyrics(from: record))
        XCTAssertTrue(lyrics.isInstrumental)
        XCTAssertTrue(lyrics.lines.isEmpty)
    }

    // MARK: - Subsonic

    func testSubsonicStructuredLyricsPreferTimedMain() throws {
        let body = try JSONDecoder().decode(SubsonicEnvelope.self, from: Data("""
        {"subsonic-response": {"status": "ok", "version": "1.16.1", "openSubsonic": true,
          "lyricsList": {"structuredLyrics": [
            {"lang": "eng", "synced": false, "line": [{"value": "Plain one"}, {"value": "Plain two"}]},
            {"lang": "eng", "synced": true, "offset": -100, "line": [{"start": 0, "value": "It's bugging me"}, {"start": 2000, "value": "Grating me"}]}
          ]}}}
        """.utf8)).subsonicResponse

        let sets = try XCTUnwrap(body.lyricsList?.structuredLyrics)
        let timed = try XCTUnwrap(sets[1].lyrics)
        XCTAssertTrue(timed.isSynced)
        XCTAssertEqual(timed.lines.map { $0.start! }, [0.1, 2.1], accuracy: 0.0001)
        XCTAssertEqual(timed.source, .subsonic)

        let plain = try XCTUnwrap(sets[0].lyrics)
        XCTAssertFalse(plain.isSynced)
        XCTAssertEqual(plain.lines.map(\.text), ["Plain one", "Plain two"])
    }

    func testSubsonicLegacyLyrics() throws {
        let body = try JSONDecoder().decode(SubsonicEnvelope.self, from: Data("""
        {"subsonic-response": {"status": "ok", "version": "1.16.1",
          "lyrics": {"artist": "Muse", "title": "Hysteria", "value": "It's bugging me\\nGrating me"}}}
        """.utf8)).subsonicResponse
        XCTAssertEqual(body.lyrics?.value, "It's bugging me\nGrating me")
    }

    // MARK: - Plex

    func testPlexLyricStreamsFromTrackMetadata() throws {
        let container = try JSONDecoder().decode(PlexLyricStreamsContainer.self, from: Data("""
        {"MediaContainer": {"size": 1, "Metadata": [{"ratingKey": "42", "Media": [{"Part": [{"Stream": [
          {"id": 1, "streamType": 2, "codec": "flac"},
          {"id": 2, "streamType": 4, "key": "/library/streams/2", "codec": "txt", "format": "txt", "provider": "com.plexapp.agents.localmedia"},
          {"id": 3, "streamType": 4, "key": "/library/streams/3", "codec": "lrc", "format": "lrc", "timed": "1", "provider": "com.plexapp.agents.lyricfind"}
        ]}]}]}]}}
        """.utf8))

        let streams = container.lyricStreams
        XCTAssertEqual(streams.map(\.key), ["/library/streams/2", "/library/streams/3"])
        XCTAssertFalse(streams[0].isLikelyTimed)
        XCTAssertTrue(streams[1].isLikelyTimed)
        XCTAssertTrue(streams[1].timed)
        XCTAssertNil(streams[0].credit)
        XCTAssertEqual(streams[1].credit, "LyricFind")
        XCTAssertFalse(streams[0].isAgent, "a sidecar is a file on the server")
        XCTAssertTrue(streams[1].isAgent, "LyricFind's are fetched, and limited")
    }

    func testPlexAgentLyricsJSON() throws {
        let container = try JSONDecoder().decode(PlexLyricsContainer.self, from: Data("""
        {"MediaContainer": {"size": 1, "Lyrics": [{"timed": true, "Line": [
          {"startOffset": 1200, "endOffset": 3000, "Span": [{"startOffset": 1200, "text": "Like the legend "}, {"startOffset": 2000, "text": "of the phoenix"}]},
          {"startOffset": 4000},
          {"startOffset": 6500, "Span": [{"text": "All ends with beginnings"}]}
        ]}]}}
        """.utf8))

        let lyrics = try XCTUnwrap(container.lyrics(credit: "LyricFind"))
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.map(\.text), ["Like the legend of the phoenix", "", "All ends with beginnings"])
        XCTAssertEqual(lyrics.lines.map { $0.start! }, [1.2, 4, 6.5], accuracy: 0.0001)
        XCTAssertEqual(lyrics.credit, "LyricFind")
    }
}

private func XCTAssertEqual(_ lhs: [Double], _ rhs: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(lhs.count, rhs.count, "counts differ: \(lhs) vs \(rhs)", file: file, line: line)
    for (l, r) in zip(lhs, rhs) {
        XCTAssertEqual(l, r, accuracy: accuracy, "\(lhs) vs \(rhs)", file: file, line: line)
    }
}
