@testable import DanceLogger
import XCTest

final class DanceLoggerTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "DanceLoggerTests"

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DanceLoggerTests-\(UUID().uuidString)", isDirectory: true)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(maxFileSize: Int = 1024 * 1024, maxTotalSize: Int = 10 * 1024 * 1024) -> DanceLogStore {
        DanceLogStore(directory: directory, maxFileSize: maxFileSize, maxTotalSize: maxTotalSize, defaults: defaults)
    }

    // MARK: - Messages

    func testInterpolationDescribesValues() {
        let count = 3
        let message: DanceLog.Message = "carrying \(count) items from \("device", privacy: .public) at \(1.5)s"
        XCTAssertEqual(message.text, "carrying 3 items from device at 1.5s")
    }

    func testPrivateValuesAreHidden() {
        let name = "Jo"
        let message: DanceLog.Message = "signed in as \(name, privacy: .private)"
        XCTAssertEqual(message.text, "signed in as <private>")
    }

    // MARK: - Redaction

    func testPlexTokenInURLIsRedacted() {
        let line = "GET http://plex.local:32400/library/parts/1/file.flac?download=1&X-Plex-Token=abc123XYZ failed"
        XCTAssertEqual(
            Redactor.redact(line),
            "GET http://plex.local:32400/library/parts/1/file.flac?download=1&X-Plex-Token=<redacted> failed"
        )
    }

    func testSubsonicCredentialsAreRedacted() {
        let line = "https://music.example.com/rest/stream?id=42&u=nick&t=26719a1196d2a940705a59634eb18eab&s=c19b2d&v=1.16.1&c=Cue"
        XCTAssertEqual(
            Redactor.redact(line),
            "https://music.example.com/rest/stream?id=42&u=nick&t=<redacted>&s=<redacted>&v=1.16.1&c=Cue"
        )
        XCTAssertEqual(Redactor.redact("ping?u=nick&p=enc:6869"), "ping?u=nick&p=<redacted>")
    }

    func testHeadersAndBodiesAreRedacted() {
        XCTAssertEqual(Redactor.redact("Authorization: Bearer eyJhbGciOi.abc-def"), "Authorization: Bearer <redacted>")
        XCTAssertEqual(Redactor.redact("Token: abc123"), "Token: <redacted>")
        XCTAssertEqual(
            Redactor.redact(#"<Server name="Den" accessToken="s3cr3t" owned="1">"#),
            #"<Server name="Den" accessToken="<redacted>" owned="1">"#
        )
        XCTAssertEqual(
            Redactor.redact(#"{"authToken":"abc","id":3}"#),
            #"{"authToken":"<redacted>","id":3}"#
        )
        XCTAssertEqual(Redactor.redact("password=hunter2&next=1"), "password=<redacted>&next=1")
    }

    func testTheQuickCheckIgnoresCase() {
        XCTAssertEqual(Redactor.redact("apiKey: abc"), "apiKey: <redacted>")
        XCTAssertEqual(Redactor.redact("API_KEY=abc"), "API_KEY=<redacted>")
        XCTAssertEqual(Redactor.redact("SECRET=abc"), "SECRET=<redacted>")
        XCTAssertEqual(Redactor.redact("x-plex-TOKEN: abc"), "x-plex-TOKEN: <redacted>")
        XCTAssertTrue(Redactor.mightContainSecret("…?t=abc"))
        XCTAssertFalse(Redactor.mightContainSecret("route → Kitchen: carrying 12 items"))
        // Ends early without reading past the last byte.
        XCTAssertFalse(Redactor.mightContainSecret("tok"))
        XCTAssertFalse(Redactor.mightContainSecret("?t"))
    }

    func testOrdinaryLinesAreLeftAlone() {
        let lines = [
            "route → Kitchen + 1: carrying 12 items from device at 34s",
            "pre-arm skipped: tokenSame=true stream=false",
            "Shazam match failed: no match",
            "keyboard shortcut pressed",
        ]
        for line in lines {
            XCTAssertEqual(Redactor.redact(line), line)
        }
    }

    // MARK: - Writing

    func testLinesAreWrittenReadably() throws {
        let store = makeStore()
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T12:22:05Z"))
        store.append(level: .error, category: "route", message: "replace failed", at: date)
        store.append(level: .info, category: "plex", message: "first\nsecond", at: date)

        let text = store.recentText()
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasSuffix(" ERROR [route] replace failed"), lines[0])
        XCTAssertTrue(lines[1].hasSuffix(" INFO  [plex] first"), lines[1])
        XCTAssertEqual(lines[2], "    second")
        XCTAssertNotNil(lines[0].range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} "#, options: .regularExpression))
    }

    func testEntriesReadBackWhatWasWritten() {
        let store = makeStore()
        store.beginSession("Cue 2026.6 (100) · iOS 27.0 · iPhone17,1")
        store.append(level: .notice, category: "route", message: "switched")
        store.append(level: .warning, category: "plex", message: "retrying\n<xml/>")

        let entries = DanceLogStore.entries(in: store.recentText())
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].isLaunch)
        XCTAssertTrue(entries[0].message.contains("Cue 2026.6 (100)"))
        XCTAssertEqual(entries[1].level, .notice)
        XCTAssertEqual(entries[1].category, "route")
        XCTAssertEqual(entries[1].message, "switched")
        XCTAssertEqual(entries[2].level, .warning)
        XCTAssertEqual(entries[2].message, "retrying\n<xml/>")
    }

    func testLongMessagesAreCut() {
        let store = makeStore()
        store.append(level: .debug, category: "plex", message: String(repeating: "a", count: 10_000))
        let text = store.recentText()
        XCTAssertTrue(text.contains("… (2000 more characters)"))
        XCTAssertLessThan(text.count, 8_200)
    }

    func testANewFileStartsWhenTheCurrentOneIsFull() {
        let store = makeStore(maxFileSize: 400)
        for index in 0..<20 {
            store.append(level: .info, category: "test", message: "line \(index) " + String(repeating: "x", count: 40))
        }
        store.flush()
        let files = store.logFiles()
        XCTAssertGreaterThan(files.count, 1)
        // Nothing is lost across the files, and they read back in order.
        let messages = DanceLogStore.entries(in: store.recentText()).map(\.message)
        XCTAssertEqual(messages.count, 20)
        XCTAssertTrue(messages[0].hasPrefix("line 0 "))
        XCTAssertTrue(messages[19].hasPrefix("line 19 "))
    }

    func testOldestFilesGoWhenTheFolderIsFull() {
        let store = makeStore(maxFileSize: 300, maxTotalSize: 1_000)
        for index in 0..<60 {
            store.append(level: .info, category: "test", message: "line \(index) " + String(repeating: "x", count: 40))
        }
        XCTAssertLessThanOrEqual(store.totalSize(), 1_000 + 300)
        let messages = DanceLogStore.entries(in: store.recentText()).map(\.message)
        XCTAssertTrue(messages.last?.hasPrefix("line 59 ") ?? false)
        XCTAssertFalse(messages.contains { $0.hasPrefix("line 0 ") })
    }

    func testRecentTextKeepsTheNewestLines() {
        let store = makeStore()
        for index in 0..<100 {
            store.append(level: .info, category: "test", message: "line \(index)")
        }
        let text = store.recentText(limit: 500)
        XCTAssertTrue(text.hasPrefix("… (earlier lines left out)\n"))
        let messages = DanceLogStore.entries(in: text).compactMap { $0.level == nil ? nil : $0.message }
        XCTAssertEqual(messages.last, "line 99")
        XCTAssertFalse(messages.contains("line 0"))
        // Cut at a line, not inside one.
        XCTAssertTrue(messages.allSatisfy { $0.hasPrefix("line ") })
    }

    func testExportStartsWithTheHeader() throws {
        let store = makeStore()
        store.append(level: .error, category: "sonos", message: "group load failed")
        let url = try store.exportFile(header: "Problem Report", title: "Cue")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("Problem Report\n\n"))
        XCTAssertTrue(text.contains("[sonos] group load failed"))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Cue Log "))
        XCTAssertEqual(url.pathExtension, "txt")
    }

    func testClearRemovesEverything() {
        let store = makeStore()
        store.append(level: .info, category: "test", message: "before")
        store.clear()
        XCTAssertTrue(store.logFiles().isEmpty)
        store.append(level: .info, category: "test", message: "after")
        XCTAssertEqual(DanceLogStore.entries(in: store.recentText()).map(\.message), ["after"])
    }

    // MARK: - Detailed Logging

    func testDetailedLoggingTurnsItselfOff() {
        let store = makeStore()
        XCTAssertFalse(store.isDetailed)
        store.isDetailed = true
        XCTAssertTrue(store.isDetailed)
        let until = try? XCTUnwrap(store.detailedUntil)
        XCTAssertEqual(until?.timeIntervalSinceNow ?? 0, DanceLogStore.detailedDuration, accuracy: 5)

        store.detailedUntil = .now.addingTimeInterval(-1)
        XCTAssertFalse(store.isDetailed)

        store.isDetailed = true
        store.isDetailed = false
        XCTAssertNil(store.detailedUntil)
    }
}
