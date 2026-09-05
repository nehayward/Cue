import XCTest
@testable import SonosKit

final class NaturalSortKeyTests: XCTestCase {

    private func sorted(_ strings: [String]) -> [String] {
        strings.sorted { NaturalSortKey.key(for: $0) < NaturalSortKey.key(for: $1) }
    }

    func testNumbersOrderByValue() {
        XCTAssertEqual(sorted(["Track 10", "Track 2", "Track 1"]), ["Track 1", "Track 2", "Track 10"])
        XCTAssertEqual(sorted(["Disc 2/01", "Disc 10/01", "Disc 1/02"]), ["Disc 1/02", "Disc 2/01", "Disc 10/01"])
    }

    func testCaseAndAccentsAreIgnored() {
        XCTAssertEqual(NaturalSortKey.key(for: "Éclair"), NaturalSortKey.key(for: "eclair"))
        XCTAssertEqual(sorted(["banana", "Apple", "cherry"]), ["Apple", "banana", "cherry"])
    }

    func testLeadingZerosDoNotChangeTheValue() {
        XCTAssertEqual(NaturalSortKey.key(for: "007"), NaturalSortKey.key(for: "7"))
    }

    func testEmptyAndPunctuation() {
        XCTAssertEqual(NaturalSortKey.key(for: ""), "")
        XCTAssertEqual(sorted(["b", "", "a"]), ["", "a", "b"])
    }
}
