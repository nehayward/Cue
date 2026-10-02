import XCTest
import OrderedCollections
@testable import SonosKit

final class CloudStorageLossyDecodingTests: XCTestCase {

    private func item(_ title: String, type: ContentType = .track) -> PlayableContent {
        PlayableContent(
            title: title,
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: .spotify, id: title, type: type, location: nil),
            metadata: nil
        )
    }

    /// Play history written by a build with a `ContentType` case this one
    /// doesn't have (the Audible branch's `audiobook`).
    private func historyWithUnknownType() throws -> Data {
        let data = try JSONEncoder().encode(OrderedSet([item("First"), item("Book"), item("Last")]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        var content = try XCTUnwrap(json[1]["content"] as? [String: Any])
        content["type"] = ["audiobook": [String: Any]()]
        json[1]["content"] = content
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testWholeDecodeFailsOnUnknownType() throws {
        let data = try historyWithUnknownType()
        XCTAssertThrowsError(try JSONDecoder().decode(OrderedSet<PlayableContent>.self, from: data))
    }

    func testLossyDecodeKeepsReadableEntries() throws {
        let data = try historyWithUnknownType()
        let result = try XCTUnwrap(OrderedSet<PlayableContent>.decodeLossily(from: data))
        let history = try XCTUnwrap(result.value as? OrderedSet<PlayableContent>)
        XCTAssertEqual(history.map(\.title), ["First", "Last"])
        XCTAssertEqual(result.dropped, 1)
    }

    func testLossyDecodeOfArray() throws {
        let data = try historyWithUnknownType()
        let result = try XCTUnwrap([PlayableContent].decodeLossily(from: data))
        XCTAssertEqual((result.value as? [PlayableContent])?.count, 2)
    }

    func testLossyDecodeRejectsNonArrays() {
        XCTAssertNil([PlayableContent].decodeLossily(from: Data("{}".utf8)))
    }
}
