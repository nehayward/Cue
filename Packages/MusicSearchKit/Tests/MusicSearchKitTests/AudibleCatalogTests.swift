@testable import MusicSearchKit
import XCTest

final class AudibleCatalogTests: XCTestCase {
    /// Audible's answer for The Fellowship of the Ring by Tolkien: two
    /// readings, a dramatisation and a short one.
    private let fellowship = """
    {"products": [
      {"asin": "B0099RKRTY", "title": "The Fellowship of the Ring", "runtime_length_min": 1147},
      {"asin": "1705047572", "title": "The Fellowship of the Ring", "runtime_length_min": 1358},
      {"asin": "B002V1A2B8", "title": "The Lord of the Rings: The Fellowship of the Ring", "runtime_length_min": 275},
      {"asin": "B002V5BUUG", "title": "The Fellowship of the Ring", "runtime_length_min": 204}
    ], "total_results": 4}
    """

    private func products() throws -> [AudibleCatalog.Product] {
        try XCTUnwrap(try JSONDecoder().decode(AudibleCatalog.Page.self, from: Data(fellowship.utf8)).products)
    }

    func testTheEditionAsLongAsTheBook() throws {
        // A rip of Andy Serkis's reading, 81,500 s: Audible's 1,358 minutes.
        XCTAssertEqual(AudibleCatalog.editions(try products(), fitting: 81_500), ["1705047572"])
        // Rob Inglis's, 1,147 minutes.
        XCTAssertEqual(AudibleCatalog.editions(try products(), fitting: 68_830), ["B0099RKRTY"])
    }

    func testNoEditionAsLong() throws {
        XCTAssertEqual(AudibleCatalog.editions(try products(), fitting: 50_000), [])
    }

    func testTheClosestFirst() {
        let products = [
            AudibleCatalog.Product(asin: "B000000001", title: nil, runtimeLengthMin: 602),
            AudibleCatalog.Product(asin: "B000000002", title: nil, runtimeLengthMin: 600),
            AudibleCatalog.Product(asin: "B000000003", title: nil, runtimeLengthMin: nil)
        ]
        XCTAssertEqual(AudibleCatalog.editions(products, fitting: 36_000), ["B000000002", "B000000001"])
    }

    func testTheTitleBeforeASubtitleOrSeries() {
        XCTAssertEqual(AudibleCatalog.searchTitle("The Fellowship of the Ring: Lord of the Rings, Book 1"), "The Fellowship of the Ring")
        XCTAssertEqual(AudibleCatalog.searchTitle("The Fellowship of the Ring (Lord of the Rings)"), "The Fellowship of the Ring")
        XCTAssertEqual(AudibleCatalog.searchTitle("Dune - Book One"), "Dune")
        XCTAssertEqual(AudibleCatalog.searchTitle("Project Hail Mary"), "Project Hail Mary")
        // Too short a head is no title: kept whole.
        XCTAssertEqual(AudibleCatalog.searchTitle("It: A Novel"), "It: A Novel")
    }

    func testTheListenersStore() {
        XCTAssertEqual(AudibleCatalog.region(for: Locale(identifier: "en_GB")), "uk")
        XCTAssertEqual(AudibleCatalog.region(for: Locale(identifier: "de_DE")), "de")
        XCTAssertEqual(AudibleCatalog.region(for: Locale(identifier: "pt_BR")), "us")
    }

    func testTheSearchAddress() throws {
        let url = try XCTUnwrap(AudibleCatalog.url(title: "The Fellowship of the Ring", author: "J. R. R. Tolkien", region: "uk"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "api.audible.co.uk")
        XCTAssertEqual(components.path, "/1.0/catalog/products")
        XCTAssertEqual(components.queryItems?.first { $0.name == "title" }?.value, "The Fellowship of the Ring")
        XCTAssertEqual(components.queryItems?.first { $0.name == "author" }?.value, "J. R. R. Tolkien")
    }
}
