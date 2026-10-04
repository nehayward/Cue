import MusicSearchKit
@testable import SonosKit
import XCTest

/// The player, the playback cache and downloads each fetch a Plex song under
/// a transcode session and client of their own: Plex ends a transcode when
/// another starts under the same session, and the cache asks for the song
/// the player has just landed on whenever a skip outruns it — which used to
/// end the player's stream before it loaded ("Couldn't play").
final class DeviceStreamTests: XCTestCase {
    private var savedFormat: Any?
    private var savedBitrate: Any?

    override func setUp() {
        super.setUp()
        savedFormat = UserDefaults.standard.object(forKey: StreamTranscoding.formatKey)
        savedBitrate = UserDefaults.standard.object(forKey: StreamTranscoding.bitrateKey)
        UserDefaults.standard.removeObject(forKey: StreamTranscoding.formatKey)
        UserDefaults.standard.removeObject(forKey: StreamTranscoding.bitrateKey)
    }

    override func tearDown() {
        for (key, value) in [(StreamTranscoding.formatKey, savedFormat), (StreamTranscoding.bitrateKey, savedBitrate)] {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    private let directURL = URL(string: "http://plex.local:32400/library/parts/4321/1700000000/file.flac?X-Plex-Token=abc123")!
    private let contentID = "a1b2c3machine%3A3%3A9876"

    private func query(for reader: DeviceStream.Reader) throws -> [String: String] {
        let url = DeviceStream.url(service: .plex, contentID: contentID, sourceURL: directURL, audioCodec: "flac", for: reader)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    /// The player keeps the names it always had.
    func testPlayerStreamsUnderCueSession() throws {
        StreamTranscoding.format = .mp3
        let player = try query(for: .player)
        XCTAssertEqual(player["session"], "cue-9876")
        XCTAssertEqual(player["X-Plex-Client-Identifier"], "Cue")
        XCTAssertEqual(
            DeviceStream.url(service: .plex, contentID: contentID, sourceURL: directURL, audioCodec: "flac"),
            DeviceStream.url(service: .plex, contentID: contentID, sourceURL: directURL, audioCodec: "flac", for: .player)
        )
    }

    func testCacheAndDownloadsNeverShareTheirTranscodeWithThePlayer() throws {
        StreamTranscoding.format = .mp3
        StreamTranscoding.bitrate = 160
        let readers: [DeviceStream.Reader] = [.player, .cache, .download]
        let queries = try readers.map { try query(for: $0) }

        XCTAssertEqual(Set(queries.map { $0["session"] }).count, readers.count, "each reader has its own session")
        XCTAssertEqual(Set(queries.map { $0["X-Plex-Client-Identifier"] }).count, readers.count, "each reader has its own client")
        XCTAssertEqual(queries[1]["session"], "cue-cache-9876")
        XCTAssertEqual(queries[2]["session"], "cue-download-9876")

        // The same song, at the same quality, whoever fetches it.
        for query in queries {
            XCTAssertEqual(query["path"], "/library/metadata/9876")
            XCTAssertEqual(query["audioCodec"], "mp3")
            XCTAssertEqual(query["musicBitrate"], "160")
            XCTAssertEqual(query["X-Plex-Token"], "abc123")
        }
    }

    /// No transcode, no session to share: everyone gets the file itself.
    func testOriginalIsTheDirectFileForEveryReader() {
        for reader in [DeviceStream.Reader.player, .cache, .download] {
            XCTAssertEqual(DeviceStream.url(service: .plex, contentID: contentID, sourceURL: directURL, audioCodec: "flac", for: reader), directURL)
        }
    }
}
