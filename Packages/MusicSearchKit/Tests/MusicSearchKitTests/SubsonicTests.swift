@testable import MusicSearchKit
import XCTest

final class SubsonicTests: XCTestCase {

    private var savedDefaults: [String: String?] = [:]
    private var savedSecrets: (password: String, salt: String)?
    private let keys = [
        "com.cue.subsonic.server",
        "com.cue.subsonic.username",
        // Legacy secret locations — only touched by the migration test.
        "com.cue.subsonic.password",
        "com.cue.subsonic.salt"
    ]

    override func setUp() {
        super.setUp()
        for key in keys {
            savedDefaults[key] = UserDefaults.standard.string(forKey: key)
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
