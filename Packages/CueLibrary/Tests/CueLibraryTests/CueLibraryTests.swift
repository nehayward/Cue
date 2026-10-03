import XCTest
@testable import CueLibrary

final class CuePinsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func album(_ id: String) -> CueItem {
        CueItem(source: .plex, kind: .album, id: id, title: "Album \(id)")
    }

    func testANewPinGoesFirstAndAPinIsOnlyThereOnce() {
        var pins = CuePins.empty
        pins.pin(album("a"), at: at(1))
        pins.pin(album("b"), at: at(2))
        XCTAssertEqual(pins.items.map(\.id), ["b", "a"])

        pins.pin(album("a"), at: at(3))
        XCTAssertEqual(pins.items.map(\.id), ["a", "b"])
        XCTAssertTrue(pins.isPinned(album("b")))

        pins.unpin(album("b"), at: at(4))
        XCTAssertEqual(pins.items.map(\.id), ["a"])
        XCTAssertFalse(pins.isPinned(album("b")))
    }

    func testPinsMadeOnTwoDevicesMergeAndTheLaterOfPinAndUnpinWins() {
        var phone = CuePins.empty
        phone.pin(album("a"), at: at(1))
        var mac = phone
        phone.pin(album("b"), at: at(2))
        mac.unpin(album("a"), at: at(3))

        let merged = phone.merged(with: mac)
        XCTAssertEqual(merged.items.map(\.id), ["b"])
        XCTAssertEqual(mac.merged(with: phone), merged)

        phone.pin(album("a"), at: at(4))
        XCTAssertEqual(phone.merged(with: mac).items.map(\.id), ["a", "b"])
    }

    func testPinsCanBeReordered() {
        var pins = CuePins.empty
        for (offset, id) in ["c", "b", "a"].enumerated() {
            pins.pin(album(id), at: at(Double(offset)))
        }
        XCTAssertEqual(pins.items.map(\.id), ["a", "b", "c"])
        pins.move(fromOffsets: [2], toOffset: 0, at: at(5))
        XCTAssertEqual(pins.items.map(\.id), ["c", "a", "b"])
    }
}

final class CueLibraryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func song(_ id: String) -> CueItem {
        CueItem(source: .subsonic, kind: .song, id: id, server: "me@home.example", title: "Song \(id)")
    }

    func testDeletingAPlaylistTakesItsPinWithIt() {
        var library = CueLibrary.empty
        let mix = library.createPlaylist(named: "Mix", with: [song("1")], at: at(0))
        library.pins.pin(mix.reference, at: at(1))
        XCTAssertTrue(library.pins.isPinned(mix.reference))

        library.deletePlaylist(id: mix.id, at: at(2))
        XCTAssertNil(library.playlist(id: mix.id))
        XCTAssertTrue(library.pins.isEmpty)
        XCTAssertEqual(library.deletedPlaylists[mix.id], at(2))
    }

    func testADeletionWinsOverOlderEditsAndLosesToNewerOnes() {
        var phone = CueLibrary.empty
        let mix = phone.createPlaylist(named: "Mix", at: at(0))
        var mac = phone

        phone.updatePlaylist(id: mix.id) { $0.append([self.song("1")], at: at(1)) }
        mac.deletePlaylist(id: mix.id, at: at(2))
        XCTAssertNil(phone.merged(with: mac).playlist(id: mix.id))
        XCTAssertEqual(mac.merged(with: phone), phone.merged(with: mac))

        phone.updatePlaylist(id: mix.id) { $0.rename("Still Here", at: at(3)) }
        let merged = phone.merged(with: mac)
        XCTAssertEqual(merged.playlist(id: mix.id)?.name.value, "Still Here")
        XCTAssertNil(merged.deletedPlaylists[mix.id])
    }

    func testAPlaylistFromAnotherDeviceMergesWithTheOneHere() {
        var phone = CueLibrary.empty
        let mix = phone.createPlaylist(named: "Mix", with: [song("1")], at: at(0))
        var macCopy = mix
        macCopy.append([song("2")], at: at(2))
        phone.updatePlaylist(id: mix.id) { $0.insert([self.song("0")], at: 0, at: at(1)) }

        phone.receive(macCopy)
        XCTAssertEqual(phone.playlist(id: mix.id)?.items.map(\.id), ["0", "1", "2"])
    }

    func testAPlaylistDeletedHereIsNotBroughtBackByAnOlderCopy() {
        var phone = CueLibrary.empty
        let mix = phone.createPlaylist(named: "Mix", at: at(0))
        phone.deletePlaylist(id: mix.id, at: at(1))
        phone.receive(mix)
        XCTAssertNil(phone.playlist(id: mix.id))
    }

    func testTheNewestPlaylistComesFirst() {
        var library = CueLibrary.empty
        let older = library.createPlaylist(named: "Older", at: at(0))
        let newer = library.createPlaylist(named: "Newer", at: at(1))
        XCTAssertEqual(library.recentPlaylists.map(\.id), [newer.id, older.id])
        library.updatePlaylist(id: older.id) { $0.append([self.song("1")], at: at(2)) }
        XCTAssertEqual(library.recentPlaylists.map(\.id), [older.id, newer.id])
    }

    func testTheLibraryRoundTrips() throws {
        var library = CueLibrary.empty
        let mix = library.createPlaylist(named: "Mix", with: (0..<50).map { song("\($0)") }, at: at(0))
        library.pins.pin(mix.reference, at: at(1))
        library.pins.pin(CueItem(source: .apple, kind: .album, id: "123", title: "Album"), at: at(2))
        let gone = library.createPlaylist(named: "Gone", at: at(3))
        library.deletePlaylist(id: gone.id, at: at(4))

        XCTAssertEqual(try CueLibrary.decoded(from: library.encoded()), library)
        XCTAssertEqual(library.merged(with: library), library)
        XCTAssertEqual(library.merged(with: .empty), library)
        XCTAssertEqual(CueLibrary.empty.merged(with: library), library)
    }

    func testUnreadableDataIsRefused() {
        XCTAssertThrowsError(try CueLibrary.decoded(from: Data()))
        XCTAssertThrowsError(try CueLibrary.decoded(from: Data([9, 1, 2])))
    }
}
