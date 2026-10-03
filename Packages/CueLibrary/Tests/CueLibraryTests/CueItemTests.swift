import XCTest
@testable import CueLibrary

final class CueItemTests: XCTestCase {
    func testAPlexArtworkURLKeepsOnlyItsPath() throws {
        let url = try XCTUnwrap(URL(string: "https://192-168-1-2.abc.plex.direct:32400/library/metadata/12/thumb/34?X-Plex-Token=secret&width=300&X-Plex-Client-Identifier=me"))
        XCTAssertEqual(CueItem.serverPath(of: url), "/library/metadata/12/thumb/34?width=300")
    }

    func testAPlexTranscodeURLKeepsItsEncodedSourcePath() throws {
        let url = try XCTUnwrap(URL(string: "https://plex.example:32400/photo/:/transcode?url=%2Flibrary%2Fmetadata%2F12%2Fthumb%2F34&width=300&X-Plex-Token=secret"))
        XCTAssertEqual(CueItem.serverPath(of: url), "/photo/:/transcode?url=%2Flibrary%2Fmetadata%2F12%2Fthumb%2F34&width=300")
    }

    func testASubsonicCoverURLLosesItsSignIn() throws {
        let url = try XCTUnwrap(URL(string: "https://me:pw@music.example/rest/getCoverArt.view?id=al-1&size=300&u=me&t=token&s=salt&v=1.16.1&c=Cue&f=json"))
        XCTAssertEqual(CueItem.serverPath(of: url), "/rest/getCoverArt.view?id=al-1&size=300")
        XCTAssertEqual(CueItem.unsigned(url), "https://music.example/rest/getCoverArt.view?id=al-1&size=300")
    }

    func testPublicArtworkIsKeptWhole() throws {
        let url = try XCTUnwrap(URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/{w}x{h}bb.jpg"))
        XCTAssertEqual(CueItem.unsigned(url), url.absoluteString)
    }

    func testASignInIsSpottedAnywhereInTheQuery() {
        XCTAssertTrue(CueItem.carriesSignIn("https://plex.example/library?x-plex-token=secret"))
        XCTAssertTrue(CueItem.carriesSignIn("/rest/stream.view?id=1&T=token"))
        XCTAssertTrue(CueItem.carriesSignIn("https://me:pw@music.example/rest"))
        XCTAssertFalse(CueItem.carriesSignIn("/library/metadata/12/thumb/34?width=300"))
        XCTAssertFalse(CueItem.carriesSignIn("al-1"))
    }

    func testAnAlbumAndAPlaylistWithOneIdStayApart() {
        let album = CueItem(source: .plex, kind: .album, id: "7", title: "Seven")
        let playlist = CueItem(source: .plex, kind: .playlist, id: "7", title: "Seven")
        XCTAssertNotEqual(album.key, playlist.key)
    }

    func testTwoSubsonicServersStayApart() {
        let home = CueItem(source: .subsonic, kind: .song, id: "1", server: "me@home.example", title: "A")
        let work = CueItem(source: .subsonic, kind: .song, id: "1", server: "me@work.example", title: "A")
        XCTAssertNotEqual(home.key, work.key)
        XCTAssertFalse(home.isSame(as: work))
    }

    func testIsSameAgreesWithTheKey() {
        let song = CueItem(source: .plex, kind: .song, id: "7", title: "Seven")
        var renamed = song
        renamed.title = "Seven (Live)"
        renamed.artwork = "/library/metadata/7/thumb/2"
        XCTAssertTrue(song.isSame(as: renamed))
        XCTAssertEqual(song.key, renamed.key)
        XCTAssertFalse(song.isSame(as: CueItem(source: .plex, kind: .album, id: "7", title: "Seven")))
        XCTAssertFalse(song.isSame(as: CueItem(source: .subsonic, kind: .song, id: "7", title: "Seven")))
    }

    func testEmptyExtrasAreLeftOutAndReadBackEmpty() throws {
        let item = CueItem(source: .apple, kind: .song, id: "1", title: "A")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(item), encoding: .utf8))
        XCTAssertFalse(json.contains("extras"))
        XCTAssertEqual(try JSONDecoder().decode(CueItem.self, from: Data(json.utf8)), item)
    }
}
