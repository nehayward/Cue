import XCTest
@testable import SonosKit

/// Times the ways a queue can reach a speaker, against a real one:
///
/// - **Queue, one at a time**: an AddURIToQueue per song, what a hand-off
///   does now.
/// - **Playlist, one at a time**: an AddURIToSavedQueue per song into a Sonos
///   playlist, what keeping a "Cue Queue" playlist in sync would cost.
/// - **Playlist → queue**: that playlist added to the queue in one request,
///   the way Cue plays any Sonos playlist; what a hand-off would cost with
///   the playlist already made. Timed to the request's answer, and to the
///   queue holding every song.
/// - **Whole queue → playlist**: SaveQueue, the speaker copying its own queue
///   into a playlist in one request, for moves between speakers.
///
/// The songs are the speaker's own queue, sent back exactly as the speaker
/// lists them, so any service works: put the music to test on the speaker
/// first, 200 songs or more. The test replaces that queue as it goes, so it
/// skips unless `CUE_BENCH_IP` names the speaker (the group's coordinator).
/// The queue is saved as a playlist before anything touches it and put back
/// at the end, even when the test fails; the speaker is paused, and stays
/// paused.
///
///     cd Packages/SonosKit
///     CUE_BENCH_IP=192.168.4.50 swift test --filter QueueTransferBenchmark
///
/// `CUE_BENCH_COUNT` sets how many songs, 200 by default.
final class QueueTransferBenchmarkTests: XCTestCase {
    private let api = SonosAPI()
    private static let playlistTitle = "Cue Queue Test"
    private static let backupTitle = "Cue Queue Test Backup"
    /// Playlist adds whose answer carried no UpdateID, so it was read back
    /// before the next add; that read is inside the playlist's time.
    private var updateIDReads = 0

    func testQueueVersusPlaylist() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ip = environment["CUE_BENCH_IP"], !ip.isEmpty else {
            throw XCTSkip("Set CUE_BENCH_IP to the speaker whose queue holds the songs to test.")
        }
        let limit = environment["CUE_BENCH_COUNT"].flatMap { Int($0) } ?? 200

        let rows = try await queueRows(ip: ip, limit: limit)
        guard !rows.isEmpty else {
            return XCTFail("The queue on \(ip) is empty: put the songs to test on it first.")
        }
        let originalLength = await api.getQueueCount(IP: ip) ?? rows.count
        await api.pause(ipAddress: ip)

        // The whole queue, saved before anything touches it and put back
        // however this ends. Its one request is also the speaker-to-speaker
        // number.
        var start = ContinuousClock.now
        let saved = try await send(ip: ip, action: "SaveQueue", [
            ("InstanceID", 0),
            ("Title", Self.backupTitle),
            ("ObjectID", "")
        ])
        let saveQueue = ContinuousClock.now - start
        let backup = try Self.playlistID(Self.required("AssignedObjectID", in: saved))
        addTeardownBlock { [self] in await self.restore(from: backup, ip: ip) }

        // 1. A playlist, one song at a time. First, so the queue's run below
        // gets whatever the speaker has cached by then, not this one.
        let created = try await send(ip: ip, action: "CreateSavedQueue", [
            ("InstanceID", 0),
            ("Title", Self.playlistTitle),
            ("EnqueuedURI", ""),
            ("EnqueuedURIMetaData", "")
        ])
        let playlist = try Self.playlistID(Self.required("AssignedObjectID", in: created))
        addTeardownBlock { [self] in try? await self.destroy(playlist, ip: ip) }
        var updateID: String
        if let assigned = Self.capture("<NewUpdateID>(.*?)</NewUpdateID>", in: created) {
            updateID = assigned
        } else {
            updateID = try await readUpdateID(of: playlist, ip: ip)
        }
        let playlistAdds = try await timeEach(rows) { row in
            updateID = try await addToPlaylist(row, id: playlist, updateID: updateID, ip: ip)
        }
        let inPlaylist = try await playlistLength(of: playlist, ip: ip)
        XCTAssertEqual(inPlaylist, rows.count, "The playlist doesn't hold every song sent.")

        // 2. The queue, one song at a time: what a hand-off does now.
        try await clearQueue(ip: ip)
        let queueAdds = try await timeEach(rows) { row in
            try await addToQueue(row, ip: ip)
        }

        // 3. The playlist into an empty queue, in one request.
        try await clearQueue(ip: ip)
        start = ContinuousClock.now
        try await queuePlaylist(playlist, ip: ip)
        let playlistRequest = ContinuousClock.now - start
        let filled = await waitForQueue(length: rows.count, ip: ip)
        let playlistFull = ContinuousClock.now - start
        XCTAssertTrue(filled, "The queue never held every song from the playlist.")

        let kinds = Dictionary(grouping: rows, by: \.kind)
            .map { "\($0.key) ×\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let fullText = filled
            ? "all \(rows.count) in after \(Self.format(playlistFull))"
            : "not all in after a minute"
        print("""

        Queue transfer benchmark: \(rows.count) songs on \(ip) (\(kinds))
          Queue, one at a time      \(Self.summary(queueAdds))
          Playlist, one at a time   \(Self.summary(playlistAdds))\(updateIDReads > 0 ? ", UpdateID read back \(updateIDReads)×" : "")
          Playlist → queue          \(Self.format(playlistRequest)) for the request, \(fullText)
          Whole queue → playlist    \(Self.format(saveQueue)) for SaveQueue of \(originalLength) songs

        """)
    }

    // MARK: - Songs

    /// A queue row as the speaker lists it, ready to send back.
    private struct Row {
        /// The `<res>` text, still escaped as it sits in the DIDL, which is
        /// the form a SOAP argument takes.
        let uri: String
        /// The row's own DIDL-Lite, escaped for a SOAP argument.
        let metadata: String
        /// The URI's scheme, for the summary: `x-sonos-http` for Apple Music,
        /// `x-sonosapi-hls-static` for Plex, `http(s)` for Subsonic.
        let kind: String
    }

    /// The first `limit` rows of the speaker's queue, read 100 at a time.
    private func queueRows(ip: String, limit: Int) async throws -> [Row] {
        var rows: [Row] = []
        var offset = 0
        while rows.count < limit {
            let page = min(100, limit - rows.count)
            let body = try await send(ip: ip, action: "Browse", endpoint: "MediaServer/ContentDirectory", [
                ("ObjectID", "Q:0"),
                ("BrowseFlag", "BrowseDirectChildren"),
                ("Filter", "*"),
                ("StartingIndex", offset),
                ("RequestedCount", page),
                ("SortCriteria", "")
            ])
            let didl = Self.unescaped(Self.capture("<Result>(.*?)</Result>", in: body) ?? "")
            let header = Self.capture("(<DIDL-Lite[^>]*>)", in: didl) ?? Self.didlHeader
            let items = Self.matches("<item\\b.*?</item>", in: didl)
            for item in items {
                guard let uri = Self.capture("<res[^>]*>(.*?)</res>", in: item), !uri.isEmpty else { continue }
                rows.append(Row(
                    uri: uri,
                    metadata: Self.escaped(header + item + "</DIDL-Lite>"),
                    kind: String(uri.prefix { $0 != ":" })
                ))
            }
            offset += items.count
            if items.count < page { break }
        }
        return Array(rows.prefix(limit))
    }

    // MARK: - Requests

    /// Adds `row` to the end of the queue, as a hand-off sends each song.
    private func addToQueue(_ row: Row, ip: String) async throws {
        try await send(ip: ip, action: "AddURIToQueue", [
            ("InstanceID", 0),
            ("EnqueuedURI", row.uri),
            ("EnqueuedURIMetaData", row.metadata),
            ("DesiredFirstTrackNumberEnqueued", 0),
            ("EnqueueAsNext", 0)
        ])
    }

    /// Adds `row` to the end of the playlist `id` and returns the playlist's
    /// new UpdateID, which the next add has to quote.
    private func addToPlaylist(_ row: Row, id: String, updateID: String, ip: String) async throws -> String {
        let body = try await send(ip: ip, action: "AddURIToSavedQueue", [
            ("InstanceID", 0),
            ("ObjectID", id),
            ("UpdateID", updateID),
            ("EnqueuedURI", row.uri),
            ("EnqueuedURIMetaData", row.metadata),
            ("AddAtIndex", 4294967295)
        ])
        if let next = Self.capture("<NewUpdateID>(.*?)</NewUpdateID>", in: body) {
            return next
        }
        updateIDReads += 1
        return try await readUpdateID(of: id, ip: ip)
    }

    /// Adds the playlist `id` to the end of the queue in one request, through
    /// the same calls Cue makes to play a Sonos playlist.
    private func queuePlaylist(_ id: String, ip: String) async throws {
        let number = id.dropFirst("SQ:".count)
        guard let playlist = await api.sonosPlaylists(IP: ip).first(where: { $0.content.id.hasSuffix("#\(number)") }) else {
            throw BenchmarkError.missing("playlist \(id)")
        }
        try await api.queuePlayable(playableContent: playlist, IP: ip, position: .end)
    }

    private func clearQueue(ip: String) async throws {
        try await send(ip: ip, action: "RemoveAllTracksFromQueue", [("InstanceID", 0)])
    }

    private func destroy(_ id: String, ip: String) async throws {
        try await send(ip: ip, action: "DestroyObject", endpoint: "MediaServer/ContentDirectory", [("ObjectID", id)])
    }

    private func readUpdateID(of playlist: String, ip: String) async throws -> String {
        let body = try await browseOne(playlist, ip: ip)
        return try Self.required("UpdateID", in: body)
    }

    private func playlistLength(of playlist: String, ip: String) async throws -> Int? {
        let body = try await browseOne(playlist, ip: ip)
        return Self.capture("<TotalMatches>(.*?)</TotalMatches>", in: body).flatMap { Int($0) }
    }

    private func browseOne(_ objectID: String, ip: String) async throws -> String {
        try await send(ip: ip, action: "Browse", endpoint: "MediaServer/ContentDirectory", [
            ("ObjectID", objectID),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 1),
            ("SortCriteria", "")
        ])
    }

    /// Waits until the queue holds `length` rows, for up to a minute.
    private func waitForQueue(length: Int, ip: String) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while ContinuousClock.now < deadline {
            if let count = await api.getQueueCount(IP: ip), count >= length { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// Puts the speaker's queue back from the backup and deletes it. The
    /// backup stays when the queue couldn't be put back, so it can still be
    /// played from the Sonos app.
    private func restore(from backup: String, ip: String) async {
        do {
            try await clearQueue(ip: ip)
            try await queuePlaylist(backup, ip: ip)
            try await destroy(backup, ip: ip)
        } catch {
            print("Couldn't put the queue back on \(ip) (\(error)); it's saved as the Sonos playlist \"\(Self.backupTitle)\".")
        }
    }

    /// Sends one SOAP action on the session queue adds use, and returns the
    /// answer; anything but a 200 throws, with the speaker's error code.
    @discardableResult
    private func send(
        ip: String,
        action: String,
        endpoint: String = "MediaRenderer/AVTransport",
        _ arguments: [(key: String, value: Any)]
    ) async throws -> String {
        guard let (data, response) = try await api.sendQueueSoapRequest(ip: ip, action: action, arguments: arguments, endpoint: endpoint) else {
            throw BenchmarkError.noAnswer(action)
        }
        let body = String(decoding: data, as: UTF8.self)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BenchmarkError.refused(action, Self.capture("<errorCode>(.*?)</errorCode>", in: body))
        }
        return body
    }

    private enum BenchmarkError: Error, CustomStringConvertible {
        case noAnswer(String)
        case refused(String, String?)
        case missing(String)

        var description: String {
            switch self {
            case let .noAnswer(action): "\(action): no answer"
            case let .refused(action, code): "\(action): refused, UPnP error \(code ?? "?")"
            case let .missing(what): "missing \(what)"
            }
        }
    }

    // MARK: - Timing

    private func timeEach(_ rows: [Row], _ body: (Row) async throws -> Void) async throws -> [Duration] {
        var times: [Duration] = []
        for row in rows {
            let start = ContinuousClock.now
            try await body(row)
            times.append(ContinuousClock.now - start)
        }
        return times
    }

    private static func summary(_ times: [Duration]) -> String {
        let seconds = times.map(Self.seconds).sorted()
        let total = seconds.reduce(0, +)
        let median = seconds[seconds.count / 2]
        let slowest = seconds.last ?? 0
        return String(
            format: "%6.1f s   %4.0f ms a song (median %.0f, slowest %.0f)",
            total, total / Double(seconds.count) * 1000, median * 1000, slowest * 1000
        )
    }

    private static func format(_ duration: Duration) -> String {
        String(format: "%.2f s", seconds(duration))
    }

    private static func seconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }

    // MARK: - XML

    private static let didlHeader = #"<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">"#

    /// "SQ:12", whichever way the speaker put it.
    private static func playlistID(_ assigned: String) -> String {
        assigned.hasPrefix("SQ:") ? assigned : "SQ:" + assigned
    }

    private static func required(_ tag: String, in body: String) throws -> String {
        guard let value = capture("<\(tag)>(.*?)</\(tag)>", in: body) else {
            throw BenchmarkError.missing(tag)
        }
        return value
    }

    /// The first capture group of `pattern` in `text`.
    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Every match of `pattern` in `text`.
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// One level of XML escaping off, `&amp;` last so what was escaped twice
    /// stays escaped once.
    private static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
