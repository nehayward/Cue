import XCTest
@testable import CueLibrary

final class OrderKeyTests: XCTestCase {
    private func assertInOrder(_ keys: [String], file: StaticString = #filePath, line: UInt = #line) {
        for (lower, upper) in zip(keys, keys.dropFirst()) {
            XCTAssertTrue(OrderKey.precedes(lower, upper), "\(lower) should sort before \(upper)", file: file, line: line)
        }
        for key in keys {
            XCTAssertTrue(OrderKey.isValid(key), "\(key) should be valid", file: file, line: line)
        }
    }

    func testAnEmptyListStartsAtA0() throws {
        XCTAssertEqual(try OrderKey.between(nil, nil), "a0")
        XCTAssertEqual(OrderKey.first, "a0")
    }

    func testAddingToTheEndCountsUpAndStaysShort() throws {
        var keys = ["a0"]
        for _ in 0..<500 {
            keys.append(try OrderKey.between(keys.last, nil))
        }
        assertInOrder(keys)
        XCTAssertEqual(Array(keys.prefix(3)), ["a0", "a1", "a2"])
        XCTAssertEqual(keys[62], "b00")
        XCTAssertLessThanOrEqual(keys.map(\.count).max() ?? 0, 3)
    }

    func testAddingToTheStartCountsDown() throws {
        var keys = ["a0"]
        for _ in 0..<500 {
            keys.insert(try OrderKey.between(nil, keys.first), at: 0)
        }
        assertInOrder(keys)
        XCTAssertEqual(keys[keys.count - 2], "Zz")
    }

    func testAKeyGoesBetweenTwoNeighbours() throws {
        XCTAssertEqual(try OrderKey.between("a0", "a1"), "a0V")
        XCTAssertEqual(try OrderKey.between("a0", "a0V"), "a0G")
        let key = try OrderKey.between("a0V", "a1")
        assertInOrder(["a0V", key, "a1"])
    }

    func testPuttingThingsInOnePlaceOverAndOverKeepsWorking() throws {
        var lower = "a0"
        let upper = "a1"
        for _ in 0..<200 {
            let key = try OrderKey.between(lower, upper)
            assertInOrder([lower, key, upper])
            lower = key
        }
        var upperKey = "a1"
        for _ in 0..<200 {
            let key = try OrderKey.between("a0", upperKey)
            assertInOrder(["a0", key, upperKey])
            upperKey = key
        }
    }

    func testManyKeysAtOnceAreInOrderAndBetweenTheirBounds() throws {
        let keys = try OrderKey.keys(between: "a0", "a1", count: 1_000)
        XCTAssertEqual(keys.count, 1_000)
        XCTAssertEqual(Set(keys).count, 1_000)
        assertInOrder(["a0"] + keys + ["a1"])
        XCTAssertLessThanOrEqual(keys.map(\.count).max() ?? 0, 5)

        assertInOrder(try OrderKey.keys(between: nil, nil, count: 300))
        assertInOrder(try OrderKey.keys(between: nil, "a0", count: 300) + ["a0"])
        XCTAssertTrue(try OrderKey.keys(between: "a0", nil, count: 0).isEmpty)
    }

    func testKeysThatTheSchemeNeverMakesAreRefused() {
        for key in ["", "a", "a00", "b0", "!0", "a0 ", "A00000000000000000000000000"] {
            XCTAssertFalse(OrderKey.isValid(key), key)
        }
        XCTAssertThrowsError(try OrderKey.between("a1", "a0"))
        XCTAssertThrowsError(try OrderKey.between("a1", "a1"))
        XCTAssertThrowsError(try OrderKey.between("a00", nil))
    }
}
