@testable import MusicSearchKit
import XCTest

final class SubsonicTests: XCTestCase {

    private var savedDefaults: [String: Any?] = [:]
    private var savedSecrets: (password: String, salt: String)?
    private let keys = [
        "com.cue.subsonic.server",
        "com.cue.subsonic.username",
        // Legacy secret locations — only touched by the migration test.
        "com.cue.subsonic.password",
        "com.cue.subsonic.salt",
        // The transcoding choice, so a test that sets it can't leak into
        // the URL tests that expect the original file.
        StreamTranscoding.formatKey,
        StreamTranscoding.bitrateKey
    ]

    override func setUp() {
        super.setUp()
        for key in keys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        savedSecrets = SubsonicAPI.storedSecrets()
    }

    override func tearDown() {
        SubsonicAPI.setSecrets(password: savedSecrets?.password, salt: savedSecrets?.salt)
        for key in keys {
            if let value = savedDefaults[key] ?? nil {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    private func storeCredentials(server: String = "http://demo.example.com:4533",
                                  username: String = "admin",
                                  password: String = "sesame",
                                  salt: String = "c19b2d") {
        UserDefaults.standard.set(server, forKey: "com.cue.subsonic.server")
        UserDefaults.standard.set(username, forKey: "com.cue.subsonic.username")
        SubsonicAPI.setSecrets(password: password, salt: salt)
    }

    // MARK: - Auth token

    /// The worked example from the Subsonic API documentation:
    /// md5("sesame" + "c19b2d") == "26719a1196d2a940705a59634eb18eab".
    func testTokenMatchesSubsonicDocumentationExample() {
        XCTAssertEqual(
            SubsonicAPI.token(password: "sesame", salt: "c19b2d"),
            "26719a1196d2a940705a59634eb18eab"
        )
    }

    // MARK: - URL building

    func testStreamURLCarriesAuthAndSongID() throws {
        storeCredentials()
        let url = try XCTUnwrap(SubsonicAPI.streamURL(for: "300001"))
        XCTAssertEqual(url.host, "demo.example.com")
        XCTAssertEqual(url.port, 4533)
        XCTAssertEqual(url.path, "/rest/stream")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["id"], "300001")
        XCTAssertEqual(items["u"], "admin")
        XCTAssertEqual(items["s"], "c19b2d")
        XCTAssertEqual(items["t"], "26719a1196d2a940705a59634eb18eab")
        XCTAssertEqual(items["v"], SubsonicAPI.apiVersion)
        XCTAssertEqual(items["c"], "Cue")
    }

    /// Sonos classifies plain-HTTP queue items by the extension it finds in
    /// the URL (UPnP 804 without one), so the song's suffix rides along as a
    /// trailing `ext` parameter the server ignores.
    func testStreamURLAppendsFileExtensionHint() throws {
        storeCredentials()
        let url = try XCTUnwrap(SubsonicAPI.streamURL(for: "300001", fileExtension: "FLAC"))
        XCTAssertTrue(url.absoluteString.hasSuffix("ext=.flac"))

        let plain = try XCTUnwrap(SubsonicAPI.streamURL(for: "300001"))
        XCTAssertFalse(plain.absoluteString.contains("ext="))
    }

    private func queryItems(of url: URL) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    // MARK: - Transcoding

    /// With a format chosen, the server converts on the way out: `format`
    /// and `maxBitRate` per the Subsonic API, a Content-Length estimate for
    /// the speaker, and the extension hint becomes the *transcoded* suffix —
    /// the speaker is handed MP3, whatever the file was.
    func testStreamURLTranscodesForSpeakerWhenMP3Chosen() throws {
        storeCredentials()
        StreamTranscoding.format = .mp3
        StreamTranscoding.bitrate = 128

        let url = try XCTUnwrap(SubsonicAPI.streamURL(for: "300001", fileExtension: "flac", destination: .speaker))
        let items = try queryItems(of: url)
        XCTAssertEqual(items["format"], "mp3")
        XCTAssertEqual(items["maxBitRate"], "128")
        XCTAssertEqual(items["estimateContentLength"], "true")
        XCTAssertEqual(items["ext"], ".mp3")
        XCTAssertTrue(url.absoluteString.hasSuffix("ext=.mp3"))

        // The device downloads the stream: no length estimate to fall short of.
        let device = try queryItems(of: XCTUnwrap(SubsonicAPI.streamURL(for: "300001", fileExtension: "flac", destination: .device)))
        XCTAssertEqual(device["format"], "mp3")
        XCTAssertNil(device["estimateContentLength"])
    }

    /// Sonos players don't decode Opus: a speaker gets MP3 in its place,
    /// while this device gets the Opus it asked for.
    func testOpusFallsBackToMP3ForSpeakersOnly() throws {
        storeCredentials()
        StreamTranscoding.format = .opus

        let speaker = try queryItems(of: XCTUnwrap(SubsonicAPI.streamURL(for: "1", fileExtension: "flac", destination: .speaker)))
        XCTAssertEqual(speaker["format"], "mp3")
        XCTAssertEqual(speaker["ext"], ".mp3")

        let device = try queryItems(of: XCTUnwrap(SubsonicAPI.streamURL(for: "1", fileExtension: "flac", destination: .device)))
        XCTAssertEqual(device["format"], "opus")
        XCTAssertEqual(device["ext"], ".opus")
    }

    /// The original-file overload (what `previewURL` and caching key off)
    /// ignores the setting, and "Original" leaves the URL exactly as before.
    func testStreamURLLeavesOriginalAloneWhenNotTranscoding() throws {
        storeCredentials()
        StreamTranscoding.format = .mp3
        let original = try queryItems(of: XCTUnwrap(SubsonicAPI.streamURL(for: "1", fileExtension: "flac")))
        XCTAssertNil(original["format"])
        XCTAssertNil(original["maxBitRate"])
        XCTAssertEqual(original["ext"], ".flac")

        StreamTranscoding.format = .original
        let speaker = try queryItems(of: XCTUnwrap(SubsonicAPI.streamURL(for: "1", fileExtension: "flac", destination: .speaker)))
        XCTAssertNil(speaker["format"])
        XCTAssertEqual(speaker["ext"], ".flac")
    }

    // MARK: - Address parsing

    /// People paste the address out of their browser, which carries the web
    /// client's own route — the REST API lives at the server root.
    func testNormalizedAddressStripsWebClientRoute() {
        XCTAssertEqual(
            SubsonicAPI.normalizedAddress("http://192.168.5.166:4533/app/#/login"),
            "http://192.168.5.166:4533"
        )
        XCTAssertEqual(
            SubsonicAPI.normalizedAddress("https://music.example.com/rest/ping?u=me"),
            "https://music.example.com"
        )
    }

    /// A reverse-proxy subpath is part of the server's address, so it stays.
    func testNormalizedAddressKeepsReverseProxySubpath() {
        XCTAssertEqual(
            SubsonicAPI.normalizedAddress("https://music.example.com/subsonic/"),
            "https://music.example.com/subsonic"
        )
    }

    func testNormalizedAddressDefaultsSchemeAndTrimsJunk() {
        XCTAssertEqual(SubsonicAPI.normalizedAddress("  nas.local:4533/  "), "http://nas.local:4533")
        XCTAssertNil(SubsonicAPI.normalizedAddress(""))
        XCTAssertNil(SubsonicAPI.normalizedAddress("   "))
    }

    /// A bare public name is tried over HTTPS before HTTP.
    func testCandidateAddressesTryHTTPSFirstForPublicNames() {
        XCTAssertEqual(
            SubsonicAPI.candidateAddresses(for: "music.example.com"),
            ["https://music.example.com", "http://music.example.com"]
        )
        XCTAssertEqual(
            SubsonicAPI.candidateAddresses(for: "music.example.com:4533/navidrome/app/#/login"),
            ["https://music.example.com:4533/navidrome", "http://music.example.com:4533/navidrome"]
        )
    }

    /// Home-network names, IP addresses and a typed scheme are used as given.
    func testCandidateAddressesKeepLocalAndExplicitAddresses() {
        XCTAssertEqual(SubsonicAPI.candidateAddresses(for: "nas.local:4533"), ["http://nas.local:4533"])
        XCTAssertEqual(SubsonicAPI.candidateAddresses(for: "192.168.1.20:4533"), ["http://192.168.1.20:4533"])
        XCTAssertEqual(SubsonicAPI.candidateAddresses(for: "localhost:4533"), ["http://localhost:4533"])
        XCTAssertEqual(SubsonicAPI.candidateAddresses(for: "http://music.example.com"), ["http://music.example.com"])
        XCTAssertEqual(SubsonicAPI.candidateAddresses(for: "https://music.example.com/"), ["https://music.example.com"])
        XCTAssertEqual(SubsonicAPI.candidateAddresses(for: "  "), [])
    }

    func testLooksPublic() {
        XCTAssertTrue(SubsonicAPI.looksPublic(host: "music.example.com"))
        XCTAssertTrue(SubsonicAPI.looksPublic(host: "nas.tail1234.ts.net"))
        XCTAssertFalse(SubsonicAPI.looksPublic(host: "nas"))
        XCTAssertFalse(SubsonicAPI.looksPublic(host: "NAS.LOCAL"))
        XCTAssertFalse(SubsonicAPI.looksPublic(host: "nas.home.arpa"))
        XCTAssertFalse(SubsonicAPI.looksPublic(host: "10.0.0.2"))
        XCTAssertFalse(SubsonicAPI.looksPublic(host: "fe80::1"))
    }

    func testLoginErrorMessages() {
        XCTAssertEqual(
            SubsonicAPI.message(forServerError: SubsonicError(code: 40, message: "Wrong username or password")),
            "Wrong username or password."
        )
        XCTAssertEqual(
            SubsonicAPI.message(forServerError: SubsonicError(code: 70, message: "Not found")),
            "Not found"
        )
        XCTAssertEqual(
            SubsonicAPI.message(forConnectionError: URLError(.cannotFindHost)),
            "Couldn't find that server. Check the address."
        )
    }

    func testCoverArtURLScalesAndNilsOutForMissingID() {
        storeCredentials()
        XCTAssertNil(SubsonicAPI.coverArtURL(for: nil))
        XCTAssertNil(SubsonicAPI.coverArtURL(for: ""))
        let url = SubsonicAPI.coverArtURL(for: "al-1", size: 300)
        XCTAssertEqual(url?.path, "/rest/getCoverArt")
        XCTAssertTrue(url?.query?.contains("size=300") ?? false)
    }

    func testStreamURLNilWithoutCredentials() {
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        SubsonicAPI.setSecrets(password: nil, salt: nil)
        XCTAssertNil(SubsonicAPI.streamURL(for: "300001"))
    }

    /// A pre-keychain login stored in UserDefaults is picked up (and adopted
    /// into the secret store) on first read.
    func testLegacyDefaultsSecretsMigrate() {
        SubsonicAPI.setSecrets(password: nil, salt: nil)
        UserDefaults.standard.set("sesame", forKey: "com.cue.subsonic.password")
        UserDefaults.standard.set("c19b2d", forKey: "com.cue.subsonic.salt")
        // Cold-cache read, as on a fresh launch after updating.
        SubsonicAPI.resetSecretsCache()

        let secrets = SubsonicAPI.storedSecrets()
        XCTAssertEqual(secrets?.password, "sesame")
        XCTAssertEqual(secrets?.salt, "c19b2d")
    }

    /// A bare host gets an http scheme; trailing slashes are dropped so the
    /// `/rest/...` path appends cleanly; a subpath install is preserved.
    func testServerAddressNormalization() throws {
        storeCredentials(server: "nas.local:4533/")
        var url = try XCTUnwrap(SubsonicAPI.streamURL(for: "1"))
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "nas.local")
        XCTAssertEqual(url.path, "/rest/stream")

        storeCredentials(server: "https://music.example.com/subsonic/")
        url = try XCTUnwrap(SubsonicAPI.streamURL(for: "1"))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.path, "/subsonic/rest/stream")
    }

    // MARK: - Decoding

    func testDecodeSearchResponse() throws {
        let json = """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "searchResult3": {
              "artist": [
                { "id": "ar-1", "name": "Daft Punk", "coverArt": "ar-1", "albumCount": 4 }
              ],
              "album": [
                { "id": "al-1", "name": "Discovery", "artist": "Daft Punk", "artistId": "ar-1",
                  "coverArt": "al-1", "songCount": 14, "duration": 3660, "year": 2001 }
              ],
              "song": [
                { "id": "tr-1", "title": "One More Time", "album": "Discovery", "albumId": "al-1",
                  "artist": "Daft Punk", "artistId": "ar-1", "coverArt": "al-1",
                  "duration": 320, "bitRate": 320, "suffix": "flac", "track": 1, "year": 2001,
                  "starred": "2024-01-01T00:00:00.000Z" }
              ]
            }
          }
        }
        """
        let body = try JSONDecoder().decode(SubsonicEnvelope.self, from: Data(json.utf8)).subsonicResponse
        XCTAssertTrue(body.isOK)
        let result = try XCTUnwrap(body.searchResult3)
        XCTAssertEqual(result.artist?.first?.name, "Daft Punk")
        XCTAssertEqual(result.album?.first?.displayName, "Discovery")
        XCTAssertEqual(result.album?.first?.songCount, 14)
        XCTAssertEqual(result.song?.first?.title, "One More Time")
        XCTAssertNotNil(result.song?.first?.starred)
    }

    func testDecodeErrorResponse() throws {
        let json = """
        {
          "subsonic-response": {
            "status": "failed",
            "version": "1.16.1",
            "error": { "code": 40, "message": "Wrong username or password." }
          }
        }
        """
        let body = try JSONDecoder().decode(SubsonicEnvelope.self, from: Data(json.utf8)).subsonicResponse
        XCTAssertFalse(body.isOK)
        XCTAssertEqual(body.error?.code, 40)
    }

    func testDecodePlaylistWithEntries() throws {
        let json = """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "playlist": {
              "id": "pl-1", "name": "Morning", "owner": "admin", "songCount": 2, "duration": 500,
              "coverArt": "pl-1",
              "entry": [
                { "id": "tr-1", "title": "A" },
                { "id": "tr-2", "title": "B" }
              ]
            }
          }
        }
        """
        let body = try JSONDecoder().decode(SubsonicEnvelope.self, from: Data(json.utf8)).subsonicResponse
        XCTAssertEqual(body.playlist?.entry?.count, 2)
        XCTAssertEqual(body.playlist?.entry?.first?.title, "A")
    }
}
