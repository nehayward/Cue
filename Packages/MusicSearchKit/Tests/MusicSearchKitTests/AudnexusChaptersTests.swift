@testable import MusicSearchKit
import XCTest

final class AudnexusChaptersTests: XCTestCase {
    /// Audible's edition: a 2 s intro and a 3 s outro inside a 1,000 s book
    /// of three chapters, the last of them the outro.
    private let audible = """
    {"asin": "B002V0QK4C", "brandIntroDurationMs": 2000, "brandOutroDurationMs": 3000,
     "isAccurate": true, "runtimeLengthMs": 1000000, "runtimeLengthSec": 1000,
     "chapters": [
       {"lengthMs": 400000, "startOffsetMs": 0, "startOffsetSec": 0, "title": "Opening Credits"},
       {"lengthMs": 597000, "startOffsetMs": 400000, "startOffsetSec": 400, "title": "Chapter 1"},
       {"lengthMs": 3000, "startOffsetMs": 997000, "startOffsetSec": 997, "title": "End Credits"}
     ]}
    """

    private func decode(_ json: String) throws -> AudnexusChapters {
        try JSONDecoder().decode(AudnexusChapters.self, from: Data(json.utf8))
    }

    func testAudiblesOwnLength() throws {
        let chapters = try XCTUnwrap(try decode(audible).chapters(fitting: 1000))
        XCTAssertEqual(chapters.map(\.title), ["Opening Credits", "Chapter 1", "End Credits"])
        XCTAssertEqual(chapters.map(\.start), [0, 400, 997])
        XCTAssertEqual(chapters.map(\.end), [400, 997, 1000])
    }

    func testARipWithoutTheBranding() throws {
        // 1,000 − 2 − 3: the intro cut from the front, the outro from the end.
        let chapters = try XCTUnwrap(try decode(audible).chapters(fitting: 995))
        XCTAssertEqual(chapters.map(\.title), ["Opening Credits", "Chapter 1"])
        XCTAssertEqual(chapters.map(\.start), [0, 398])
        XCTAssertEqual(chapters.map(\.end), [398, 995])
    }

    func testAnotherEditionIsLeftAlone() throws {
        XCTAssertNil(try decode(audible).chapters(fitting: 1500))
    }

    func testAudiobookshelfsNotFound() throws {
        let answer = try decode(#"{"error": "Chapters not found", "stringKey": "MessageChaptersNotFound"}"#)
        XCTAssertNotNil(answer.error)
        XCTAssertNil(answer.chapters(fitting: 1000))
    }

    func testPlexGuid() {
        XCTAssertEqual(AudnexusChapters.asin(fromPlexGuid: "com.plexapp.agents.audnexus://B002V0QK4C?lang=en")?.asin, "B002V0QK4C")
        let regional = AudnexusChapters.asin(fromPlexGuid: "com.plexapp.agents.audnexus://B002V0QK4C_uk?lang=en")
        XCTAssertEqual(regional?.asin, "B002V0QK4C")
        XCTAssertEqual(regional?.region, "uk")
        XCTAssertNil(AudnexusChapters.asin(fromPlexGuid: "plex://album/5d07c1a2403c640290f3c8a1"))
        XCTAssertNil(AudnexusChapters.asin(fromPlexGuid: nil))
    }
}

final class AudiobookTextTests: XCTestCase {
    func testPlexBreaks() {
        let summary = "Continuing the epic tale begun in The Fellowship of the Ring.<br /><br />The Fellowship is scattered."
        XCTAssertEqual(AudiobookText.plain(summary), "Continuing the epic tale begun in The Fellowship of the Ring.\n\nThe Fellowship is scattered.")
    }

    func testAudiobookshelfParagraphsAndEntities() {
        let description = "<p><b>Ryland Grace</b> is the sole survivor &amp; he doesn&#39;t know it.</p><p>Two corpses&nbsp;for company.</p>"
        XCTAssertEqual(AudiobookText.plain(description), "Ryland Grace is the sole survivor & he doesn't know it.\n\nTwo corpses for company.")
    }

    func testListsAndUnknownEntities() {
        XCTAssertEqual(AudiobookText.plain("<ul><li>One</li><li>Two</li></ul>"), "• One\n• Two")
        XCTAssertEqual(AudiobookText.plain("Fish &chips; &amp;lt;"), "Fish &chips; &lt;")
    }

    func testPlainTextIsUntouched() {
        XCTAssertEqual(AudiobookText.plain("  Just a summary.\n"), "Just a summary.")
    }
}
