import XCTest
@testable import MusicSearchKit

/// Maps pages of the signed-in user's collection
/// (`/v2/userCollection…/me/relationships/items`). The documents are written
/// to the JSON:API shape the other v2 relationship pages answer with, not
/// captured: reading a collection takes a user's token.
final class TidalCollectionTests: XCTestCase {

    /// The decoder `TidalAPI` uses.
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func page(_ json: String) throws -> TidalRelationshipPage {
        try decoder.decode(TidalRelationshipPage.self, from: Data(json.utf8))
    }

    func testPlaylistsUseTheirOwnIDAndKeepThePageOrder() throws {
        let page = try page(#"""
        {
          "data": [
            {"id": "b2", "type": "playlists", "meta": {"addedAt": "2026-09-01T10:00:00Z"}},
            {"id": "a1", "type": "playlists", "meta": {"addedAt": "2026-08-01T10:00:00Z"}},
            {"id": "m1", "type": "mixes"}
          ],
          "included": [
            {"id": "a1", "type": "playlists", "attributes": {"name": "Older", "numberOfItems": 3}},
            {"id": "b2", "type": "playlists",
             "attributes": {"name": "Road Trip", "numberOfItems": 12,
                            "externalLinks": [{"href": "https://tidal.com/browse/playlist/b2", "meta": {"type": "TIDAL_SHARING"}}]},
             "relationships": {"coverArt": {"data": [{"id": "art1", "type": "artworks"}]}}},
            {"id": "art1", "type": "artworks",
             "attributes": {"mediaType": "IMAGE", "files": [{"href": "https://resources.tidal.com/images/x/640x640.jpg", "meta": {"width": 640, "height": 640}}]}},
            {"id": "m1", "type": "mixes", "attributes": {"title": "My Mix 1"}}
          ],
          "links": {"meta": {"nextCursor": "next-page"}}
        }
        """#)

        let playlists = page.resources.compactMap { page.playlist($0) }
        XCTAssertEqual(playlists.map(\.id), ["b2", "a1"])
        XCTAssertEqual(playlists.first?.name, "Road Trip")
        XCTAssertEqual(playlists.first?.numberOfTracks, 12)
        XCTAssertEqual(playlists.first?.imageUrls.count, 1)
        XCTAssertEqual(page.links?.meta?.nextCursor, "next-page")
    }

    func testAlbumsCarryCoverAndArtists() throws {
        let page = try page(#"""
        {
          "data": [{"id": "100", "type": "albums"}],
          "included": [
            {"id": "100", "type": "albums",
             "attributes": {"title": "OK Computer", "albumType": "ALBUM", "releaseDate": "1997-05-21", "numberOfItems": 12},
             "relationships": {"coverArt": {"data": [{"id": "art", "type": "artworks"}]},
                               "artists": {"data": [{"id": "7", "type": "artists"}]}}},
            {"id": "7", "type": "artists", "attributes": {"name": "Radiohead"}},
            {"id": "art", "type": "artworks",
             "attributes": {"files": [{"href": "https://resources.tidal.com/images/y/640x640.jpg", "meta": {"width": 640, "height": 640}}]}}
          ]
        }
        """#)

        let album = try XCTUnwrap(page.resources.compactMap { page.album($0) }.first)
        XCTAssertEqual(album.title, "OK Computer")
        XCTAssertEqual(album.artists.first?.name, "Radiohead")
        XCTAssertFalse(album.imageCover?.isEmpty ?? true)
        XCTAssertFalse(album.isSingleOrEP)
        XCTAssertNil(page.links)
    }

    func testTracksSkipVideos() throws {
        let page = try page(#"""
        {
          "data": [{"id": "1", "type": "tracks"}, {"id": "2", "type": "videos"}],
          "included": [
            {"id": "1", "type": "tracks", "attributes": {"title": "Airbag", "duration": "PT4M44S"}},
            {"id": "2", "type": "videos", "attributes": {"title": "Karma Police (Video)"}}
          ]
        }
        """#)

        let tracks = page.resources.filter { $0.type == "tracks" }.compactMap { page.track($0, album: nil) }
        XCTAssertEqual(tracks.map(\.title), ["Airbag"])
        XCTAssertEqual(tracks.first?.duration, 284)
    }
}
