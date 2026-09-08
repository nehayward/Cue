@testable import MusicSearchKit
import XCTest

final class StreamTranscodingTests: XCTestCase {

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

    // MARK: - Setting

    func testUnsetReadsAsOriginalAtDefaultBitrate() {
        XCTAssertEqual(StreamTranscoding.format, .original)
        XCTAssertFalse(StreamTranscoding.isEnabled)
        XCTAssertEqual(StreamTranscoding.bitrate, StreamTranscoding.defaultBitrate)
    }

    func testOutOfRangeBitrateFallsBackToDefault() {
        UserDefaults.standard.set(7, forKey: StreamTranscoding.bitrateKey)
        XCTAssertEqual(StreamTranscoding.bitrate, StreamTranscoding.defaultBitrate)
        StreamTranscoding.bitrate = 96
        XCTAssertEqual(StreamTranscoding.bitrate, 96)
    }

    /// The suffix a stream really arrives with: the file's own when nothing
    /// is transcoded, the target otherwise — and MP3, not Opus, for a
    /// speaker, which can't play Opus.
    func testEffectiveFileExtensionPerDestination() {
        XCTAssertEqual(StreamTranscoding.fileExtension(for: .speaker, original: "flac"), "flac")
        XCTAssertNil(StreamTranscoding.fileExtension(for: .device, original: nil))

        StreamTranscoding.format = .opus
        XCTAssertEqual(StreamTranscoding.format(for: .speaker), .mp3)
        XCTAssertEqual(StreamTranscoding.format(for: .device), .opus)
        XCTAssertEqual(StreamTranscoding.fileExtension(for: .speaker, original: "flac"), "mp3")
        XCTAssertEqual(StreamTranscoding.fileExtension(for: .device, original: "flac"), "opus")
    }

    // MARK: - Plex

    func testPlexPlaybackURLIsTheDirectFileWhenNotTranscoding() {
        XCTAssertEqual(PlexAPI.playbackStreamURL(from: directURL, ratingKey: "9876"), directURL)
    }

    /// The universal transcoder, asked for the same track by `ratingKey`
    /// on the same server with the same token, in the chosen codec at the
    /// chosen bitrate, with a session of its own.
    func testPlexPlaybackURLUsesUniversalTranscoder() throws {
        StreamTranscoding.format = .mp3
        StreamTranscoding.bitrate = 160

        let url = PlexAPI.playbackStreamURL(from: directURL, ratingKey: "9876")
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "plex.local")
        XCTAssertEqual(url.port, 32400)
        XCTAssertEqual(url.path, "/music/:/transcode/universal/start.mp3")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["path"], "/library/metadata/9876")
        XCTAssertEqual(items["protocol"], "http")
        XCTAssertEqual(items["audioCodec"], "mp3")
        XCTAssertEqual(items["musicBitrate"], "160")
        XCTAssertEqual(items["directPlay"], "0")
        XCTAssertEqual(items["session"], "cue-9876")
        XCTAssertEqual(items["X-Plex-Token"], "abc123")
        XCTAssertEqual(items["X-Plex-Client-Identifier"], "Cue")
    }

    func testPlexPlaybackURLOpusTargetsOpusContainer() {
        StreamTranscoding.format = .opus
        let url = PlexAPI.playbackStreamURL(from: directURL, ratingKey: "9876")
        XCTAssertEqual(url.path, "/music/:/transcode/universal/start.opus")
        XCTAssertTrue(url.query?.contains("audioCodec=opus") == true)
    }

    /// No rating key, no transcode: the direct file still plays.
    func testPlexPlaybackURLNeedsARatingKey() {
        StreamTranscoding.format = .mp3
        XCTAssertEqual(PlexAPI.playbackStreamURL(from: directURL, ratingKey: ""), directURL)
    }
}
