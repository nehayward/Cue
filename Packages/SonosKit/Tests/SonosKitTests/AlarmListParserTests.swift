import XCTest
@testable import SonosKit

final class AlarmListParserTests: XCTestCase {

    private func loadAlarmsXML() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ListAlarms", withExtension: "xml"))
        return try String(contentsOf: url)
    }

    /// Every alarm in a normal (double-escaped) response must parse, including
    /// music alarms whose `ProgramMetaData` carries escaped DIDL with quotes
    /// and angle brackets.
    func testParsesAllAlarmsIncludingMusicMetadata() throws {
        let xml = try loadAlarmsXML()
        let alarms = AlarmListParser().parseAlarms(from: xml)

        XCTAssertEqual(alarms.count, 3, "All three alarms should parse, not just the buzzer")

        let ids = Set(alarms.map(\.id))
        XCTAssertEqual(ids, ["9", "14", "21"])
    }

    /// Required attributes that sit *after* ProgramMetaData (Volume, PlayMode,
    /// IncludeLinkedZones) must still be read correctly even when the metadata
    /// contains embedded quotes.
    func testParsesAttributesAfterMetadata() throws {
        let xml = try loadAlarmsXML()
        let alarms = AlarmListParser().parseAlarms(from: xml)

        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })

        let buzzer = try XCTUnwrap(byID["9"])
        XCTAssertEqual(buzzer.volume, 25)
        XCTAssertTrue(buzzer.enabled)
        XCTAssertEqual(buzzer.roomID, "RINCON_AAAAAAAAAAAA01400")
        XCTAssertEqual(buzzer.programMetaData, "")

        let radio = try XCTUnwrap(byID["14"])
        XCTAssertEqual(radio.volume, 40)
        XCTAssertTrue(radio.shuffle)
        XCTAssertEqual(radio.roomID, "RINCON_BBBBBBBBBBBB01400")
        XCTAssertTrue(radio.programMetaData?.contains("DIDL-Lite") ?? false)

        let spotify = try XCTUnwrap(byID["21"])
        XCTAssertEqual(spotify.volume, 15)
        XCTAssertFalse(spotify.enabled)
        XCTAssertTrue(spotify.includeLinkedZones)
        XCTAssertEqual(spotify.roomID, "RINCON_CCCCCCCCCCCC01400")
    }

    /// Some firmware/services emit ProgramMetaData escaped a single level, so
    /// after decoding the DIDL contains literal `<`/`>`. The old
    /// `<Alarm[^>]+/>` matcher stopped at the first such `>` and dropped the
    /// music alarm, returning only the buzzer. The anchored matcher must return
    /// both.
    func testParsesSingleEscapedMetadataAlarm() {
        let xml = """
        <r><CurrentAlarmList>&lt;Alarms&gt;\
        &lt;Alarm ID="9" StartTime="07:00:00" Duration="" Recurrence="DAILY" Enabled="1" RoomUUID="RINCON_A" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="NORMAL" Volume="25" IncludeLinkedZones="0"/&gt;\
        &lt;Alarm ID="40" StartTime="06:00:00" Duration="" Recurrence="DAILY" Enabled="1" RoomUUID="RINCON_B" ProgramURI="x-sonos-http:t" ProgramMetaData="&lt;DIDL-Lite&gt;&lt;item&gt;&lt;dc:title&gt;Song&lt;/dc:title&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;" PlayMode="SHUFFLE" Volume="42" IncludeLinkedZones="0"/&gt;\
        &lt;/Alarms&gt;</CurrentAlarmList></r>
        """

        let alarms = AlarmListParser().parseAlarms(from: xml)
        XCTAssertEqual(Set(alarms.map(\.id)), ["9", "40"])

        let music = try? XCTUnwrap(alarms.first(where: { $0.id == "40" }))
        XCTAssertEqual(music?.volume, 42)
        XCTAssertTrue(music?.shuffle ?? false)
    }

    /// `xmlEntityDecodedOnce` must decode exactly one entity level so that a
    /// double-escaped quote (`&amp;quot;`) becomes `&quot;`, not a bare `"`.
    func testSingleLevelEntityDecode() {
        XCTAssertEqual("&amp;quot;".xmlEntityDecodedOnce, "&quot;")
        XCTAssertEqual("&lt;Alarms&gt;".xmlEntityDecodedOnce, "<Alarms>")
        XCTAssertEqual("&amp;lt;".xmlEntityDecodedOnce, "&lt;")
        XCTAssertEqual("plain text".xmlEntityDecodedOnce, "plain text")
    }
}
