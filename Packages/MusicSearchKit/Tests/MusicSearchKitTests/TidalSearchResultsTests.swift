import XCTest
@testable import MusicSearchKit

/// Decodes a captured (trimmed) `GET /v2/searchResults?filter[query]=radiohead creep`
/// response — the endpoint shape that replaced `/v2/searchResults/{query}`.
final class TidalSearchResultsTests: XCTestCase {

    /// The decoder `TidalAPI` uses.
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func decodedResult() throws -> TidalResult {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tidalSearchResults", withExtension: "json"))
        return try decoder.decode(TidalApiResponse.self, from: Data(contentsOf: url)).toTidalResult
    }

    func testDecodesArrayShapedSearchDocument() throws {
        let result = try decodedResult()
        XCTAssertEqual(result.tracks.count, 3)
        XCTAssertEqual(result.albums.count, 3)
        XCTAssertEqual(result.playlists.count, 3)
    }

    /// Artists pulled in only to decorate tracks must not show up as artist
    /// hits, and hits keep the search's rank order rather than `included`'s
    /// id order.
    func testKeepsOnlyRankedHitsInOrder() throws {
        let result = try decodedResult()
        XCTAssertEqual(result.artists.map(\.name), ["Radiohead", "Creep"])
        XCTAssertEqual(result.albums.map(\.title), ["Creep", "Creep EP", "OK Computer"])
        XCTAssertEqual(result.playlists.first?.name, "Radiohead Essentials")
    }

    func testTracksCarryAlbumArtworkAndArtists() throws {
        let track = try XCTUnwrap(decodedResult().tracks.first)
        XCTAssertEqual(track.title, "Creep")
        XCTAssertEqual(track.artists.first?.name, "Radiohead")
        XCTAssertEqual(track.album?.id, "58990484")
        XCTAssertFalse(track.album?.imageCover?.isEmpty ?? true)
    }

    func testSearchWithNoMatchesDecodesEmpty() throws {
        let json = #"{"data":[{"id":"x","type":"searchResults","relationships":{"tracks":{"data":[]},"albums":{"data":[]},"artists":{"data":[]},"playlists":{"data":[]}}}]}"#
        let result = try decoder.decode(TidalApiResponse.self, from: Data(json.utf8)).toTidalResult
        XCTAssertTrue(result.tracks.isEmpty)
        XCTAssertTrue(result.artists.isEmpty)
    }
}
