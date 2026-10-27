@testable import MusicSearchKit
import XCTest

/// Decoding a music library's collections and what they hold.
final class PlexCollectionTests: XCTestCase {

    /// Plex sends a collection's count as a string, where its other counts
    /// are numbers. Either reads, and drives the row's "12 albums".
    func testCollectionsReadTheirCountAsStringOrNumber() throws {
        let collections = try decoded(PlexCollectionContainer.self, """
        { "MediaContainer": { "size": 3, "totalSize": 42, "Metadata": [
          { "ratingKey": "500", "key": "/library/collections/500/children", "type": "collection",
            "title": "Blue Note Essentials", "subtype": "album", "summary": "",
            "thumb": "/library/collections/500/composite/1700000000", "childCount": "12" },
          { "ratingKey": "501", "type": "collection", "title": "Desert Island",
            "subtype": "album", "childCount": 1 },
          { "ratingKey": "502", "type": "collection", "title": "Singers",
            "subtype": "artist", "childCount": "3" }
        ] } }
        """)
        XCTAssertEqual(collections.totalSize, 42)
        XCTAssertEqual(collections.metadata.map(\.childCount), [12, 1, 3])
        XCTAssertEqual(collections.metadata.map(\.itemCountLabel), ["12 albums", "1 album", "3 artists"])
    }

    /// A collection without a poster of its own has only the composite of
    /// its covers.
    func testCollectionKeepsItsComposite() throws {
        let collections = try decoded(PlexCollectionContainer.self, """
        { "MediaContainer": { "size": 1, "Metadata": [
          { "ratingKey": "501", "type": "collection", "title": "Desert Island",
            "composite": "/library/collections/501/composite/1" }
        ] } }
        """)
        XCTAssertNil(collections.metadata.first?.thumb)
        XCTAssertEqual(collections.metadata.first?.composite, "/library/collections/501/composite/1")
        XCTAssertNil(collections.metadata.first?.itemCountLabel)
    }

    /// Whether a collection is smart, and how it's sorted, read from a
    /// string, a number or a boolean; absent, it's a plain collection in
    /// Plex's default order.
    func testSmartAndSortReadInAnyForm() throws {
        let collections = try decoded(PlexCollectionContainer.self, """
        { "MediaContainer": { "size": 5, "Metadata": [
          { "ratingKey": "1", "title": "Recently Added Jazz", "smart": "1", "collectionSort": "2" },
          { "ratingKey": "2", "title": "Five Stars", "smart": true, "collectionSort": 0 },
          { "ratingKey": "3", "title": "Road Trip", "smart": 0, "collectionSort": 2 },
          { "ratingKey": "4", "title": "Rainy Days", "smart": "0", "collectionSort": "1" },
          { "ratingKey": "5", "title": "Desert Island" }
        ] } }
        """)
        XCTAssertEqual(collections.metadata.map(\.smart), [true, true, false, false, false])
        XCTAssertEqual(collections.metadata.map(\.isCustomSorted), [true, false, true, false, false])
    }

    /// The server returns a collection's items in the order they were
    /// placed, whatever the collection's sort; Release Date and Alphabetical
    /// are put in order here. Alphabetical goes by Plex's sort title, which
    /// drops "The"; Release Date by original release date, else year, with
    /// undated items last.
    func testItemsComeInTheCollectionsOrder() throws {
        let items = try decoded(PlexCollectionItemsContainer.self, """
        { "MediaContainer": { "size": 4, "Metadata": [
          { "ratingKey": "2", "key": "/library/metadata/2/children", "guid": "plex://album/2", "type": "album",
            "title": "Voulez-Vous", "summary": "", "year": 1979, "originallyAvailableAt": "1979-04-23" },
          { "ratingKey": "1", "key": "/library/metadata/1/children", "guid": "plex://album/1", "type": "album",
            "title": "The Album", "titleSort": "Album", "summary": "", "year": 1977, "originallyAvailableAt": "1977-12-12" },
          { "ratingKey": "3", "key": "/library/metadata/3/children", "guid": "plex://album/3", "type": "album",
            "title": "Arrival", "summary": "", "year": 1976 },
          { "ratingKey": "4", "key": "/library/metadata/4/children", "guid": "plex://album/4", "type": "album",
            "title": "Bootleg", "summary": "" }
        ] } }
        """).metadata

        XCTAssertEqual(items.inCollectionOrder(.custom).map(\.title), ["Voulez-Vous", "The Album", "Arrival", "Bootleg"])
        XCTAssertEqual(items.inCollectionOrder(.alphabetical).map(\.title), ["The Album", "Arrival", "Bootleg", "Voulez-Vous"])
        XCTAssertEqual(items.inCollectionOrder(.releaseDate).map(\.title), ["Arrival", "The Album", "Voulez-Vous", "Bootleg"])
    }

    /// A collection that doesn't say how it's sorted is in Plex's default,
    /// Release Date.
    func testUnstatedSortIsReleaseDate() throws {
        let collections = try decoded(PlexCollectionContainer.self, """
        { "MediaContainer": { "size": 2, "Metadata": [
          { "ratingKey": "1", "title": "Default" },
          { "ratingKey": "2", "title": "Sorted", "collectionSort": "1" }
        ] } }
        """)
        XCTAssertEqual(collections.metadata.map(\.sortOrder), [.releaseDate, .alphabetical])
    }

    /// A library with no collections sends no `Metadata` at all.
    func testLibraryWithoutCollectionsIsEmpty() throws {
        let collections = try decoded(PlexCollectionContainer.self, """
        { "MediaContainer": { "size": 0, "totalSize": 0 } }
        """)
        XCTAssertTrue(collections.metadata.isEmpty)
        XCTAssertEqual(collections.totalSize, 0)
    }

    /// One album that doesn't decode drops on its own; the rest of the
    /// collection still shows.
    func testCollectionItemsDropOnlyWhatDoesNotDecode() throws {
        let items = try decoded(PlexCollectionItemsContainer.self, """
        { "MediaContainer": { "size": 3, "totalSize": 3, "Metadata": [
          { "ratingKey": "900", "key": "/library/metadata/900/children", "guid": "plex://album/900",
            "type": "album", "title": "Blue Train", "parentTitle": "John Coltrane", "summary": "", "year": 1958 },
          { "ratingKey": "901", "type": "album", "title": "Missing Its Key" },
          { "ratingKey": "902", "key": "/library/metadata/902/children", "guid": "plex://album/902",
            "type": "album", "title": "Moanin'", "parentTitle": "Art Blakey", "summary": "" }
        ] } }
        """)
        XCTAssertEqual(items.metadata.map(\.title), ["Blue Train", "Moanin'"])
        XCTAssertEqual(items.totalSize, 3)
    }

    private func decoded<T: Codable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(PlexContainer<T>.self, from: Data(json.utf8)).mediaContainer
    }
}
