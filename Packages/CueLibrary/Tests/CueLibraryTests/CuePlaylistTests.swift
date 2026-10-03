import XCTest
@testable import CueLibrary

final class CuePlaylistTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func song(_ id: String, source: CueItem.Source = .apple) -> CueItem {
        CueItem(source: source, kind: .song, id: id, title: "Song \(id)")
    }

    private func ids(_ playlist: CuePlaylist) -> [String] {
        playlist.items.map(\.id)
    }

    private func playlist(_ songs: [String]) -> CuePlaylist {
        CuePlaylist(id: "p", name: "Mix", items: songs.map { song($0) }, at: t0)
    }

    // MARK: - Editing

    func testSongsFromDifferentServicesSitSideBySide() {
        var mix = CuePlaylist(id: "p", name: "Mix", at: t0)
        mix.append([song("1", source: .apple), song("2", source: .plex), song("3", source: .subsonic)], at: at(1))
        XCTAssertEqual(mix.items.map(\.source), [.apple, .plex, .subsonic])
        XCTAssertEqual(mix.count, 3)
    }

    func testInsertingPutsSongsBeforeTheEntryAtTheIndex() {
        var mix = playlist(["a", "b", "c"])
        mix.insert([song("x"), song("y")], at: 1, at: at(1))
        XCTAssertEqual(ids(mix), ["a", "x", "y", "b", "c"])
        mix.insert([song("z")], at: 0, at: at(2))
        XCTAssertEqual(ids(mix), ["z", "a", "x", "y", "b", "c"])
        mix.insert([song("end")], at: 99, at: at(3))
        XCTAssertEqual(ids(mix).last, "end")
    }

    func testOneSongCanBeInAPlaylistTwice() {
        var mix = playlist(["a"])
        mix.append([song("a")], at: at(1))
        XCTAssertEqual(ids(mix), ["a", "a"])
        XCTAssertTrue(mix.contains(song("a")))
        XCTAssertFalse(mix.contains(song("a", source: .plex)))
    }

    func testMovingFollowsOnMove() {
        var mix = playlist(["a", "b", "c", "d"])
        mix.move(fromOffsets: [0], toOffset: 3, at: at(1))
        XCTAssertEqual(ids(mix), ["b", "c", "a", "d"])

        mix = playlist(["a", "b", "c", "d"])
        mix.move(fromOffsets: [3], toOffset: 0, at: at(1))
        XCTAssertEqual(ids(mix), ["d", "a", "b", "c"])

        mix = playlist(["a", "b", "c", "d"])
        mix.move(fromOffsets: [0, 2], toOffset: 4, at: at(1))
        XCTAssertEqual(ids(mix), ["b", "d", "a", "c"])
    }

    func testAMoveTouchesOnlyWhatMoved() {
        var mix = playlist(["a", "b", "c", "d"])
        let before = mix.entries.elements
        mix.move(fromOffsets: [3], toOffset: 1, at: at(1))
        let changed = mix.entries.elements.filter { $0.changedAt == at(1) }
        XCTAssertEqual(changed.map(\.item.id), ["d"])
        XCTAssertEqual(Set(mix.entries.elements.map(\.order)).subtracting(before.map(\.order)).count, 1)
    }

    func testDroppingASongWhereItIsChangesNothing() {
        var mix = playlist(["a", "b", "c"])
        let before = mix
        mix.move(fromOffsets: [1], toOffset: 1, at: at(1))
        mix.move(fromOffsets: [1], toOffset: 2, at: at(1))
        XCTAssertEqual(mix, before)
    }

    func testRemovingLeavesATombstone() {
        var mix = playlist(["a", "b", "c"])
        let removedID = mix.entries.elements[1].id
        mix.remove(atOffsets: [1], at: at(1))
        XCTAssertEqual(ids(mix), ["a", "c"])
        XCTAssertEqual(mix.entries.removed, [removedID: at(1)])
        XCTAssertEqual(mix.modifiedAt, at(1))
    }

    // MARK: - Merging

    func testSongsAddedOnTwoDevicesBothSurvive() {
        let start = playlist(["a", "b"])
        var phone = start
        var mac = start
        phone.append([song("phone")], at: at(1))
        mac.insert([song("mac")], at: 0, at: at(2))

        let merged = phone.merged(with: mac)
        XCTAssertEqual(ids(merged), ["mac", "a", "b", "phone"])
        XCTAssertEqual(mac.merged(with: phone), merged)
    }

    func testMergingIsIdempotent() {
        var mix = playlist(["a", "b", "c"])
        mix.remove(atOffsets: [0], at: at(1))
        mix.rename("Renamed", at: at(2))
        XCTAssertEqual(mix.merged(with: mix), mix)
    }

    func testTheLaterOfAMoveAndARemovalWins() {
        let start = playlist(["a", "b", "c"])
        var phone = start
        var mac = start
        phone.move(fromOffsets: [0], toOffset: 3, at: at(2))
        mac.remove(atOffsets: [0], at: at(1))
        XCTAssertEqual(ids(phone.merged(with: mac)), ["b", "c", "a"])

        phone = start
        mac = start
        phone.move(fromOffsets: [0], toOffset: 3, at: at(1))
        mac.remove(atOffsets: [0], at: at(2))
        XCTAssertEqual(ids(phone.merged(with: mac)), ["b", "c"])
        XCTAssertEqual(ids(mac.merged(with: phone)), ["b", "c"])
    }

    func testSongsPutInOnePlaceAtOnceSortTheSameEverywhereAndMakeRoomAfter() {
        let start = playlist(["a", "b"])
        var phone = start
        var mac = start
        phone.insert([song("phone")], at: 1, at: at(1))
        mac.insert([song("mac")], at: 1, at: at(1))

        var merged = phone.merged(with: mac)
        XCTAssertEqual(merged, mac.merged(with: phone))
        XCTAssertEqual(Set(ids(merged)[1...2]), ["phone", "mac"])
        // The two now share a key; a song dropped between them still lands
        // between them.
        XCTAssertEqual(merged.entries.elements[1].order, merged.entries.elements[2].order)
        merged.insert([song("between")], at: 2, at: at(2))
        XCTAssertEqual(ids(merged).count, 5)
        XCTAssertEqual(ids(merged)[2], "between")
        XCTAssertEqual(ids(merged).first, "a")
        XCTAssertEqual(ids(merged).last, "b")
        let orders = merged.entries.elements.map(\.order)
        XCTAssertEqual(Set(orders).count, orders.count)
    }

    func testARenameAndANewCoverMadeApartBothSurvive() {
        let start = playlist(["a"])
        var phone = start
        var mac = start
        phone.rename("Road Trip", at: at(1))
        mac.setCover(.artwork(song("a")), at: at(2))
        mac.rename("Older Name", at: at(0.5))

        let merged = phone.merged(with: mac)
        XCTAssertEqual(merged.name.value, "Road Trip")
        XCTAssertEqual(merged.cover.value, .artwork(song("a")))
        XCTAssertEqual(mac.merged(with: phone), merged)
    }

    func testRenamesAtTheSameMomentAgree() {
        let start = playlist([])
        var phone = start
        var mac = start
        phone.rename("Phone", at: at(1))
        mac.rename("Mac", at: at(1))
        XCTAssertEqual(phone.merged(with: mac).name, mac.merged(with: phone).name)
    }

    func testAnotherPlaylistIsNotMergedIn() {
        let mine = playlist(["a"])
        let other = CuePlaylist(id: "q", name: "Other", items: [song("b")], at: t0)
        XCTAssertEqual(mine.merged(with: other), mine)
    }

    func testReplacingASongKeepsItsPlace() {
        var mix = playlist(["a", "b", "c"])
        let entry = mix.entries.elements[1]
        mix.replaceItem(entryID: entry.id, with: song("b", source: .plex), at: at(1))
        XCTAssertEqual(mix.items.map(\.source), [.apple, .plex, .apple])
        XCTAssertEqual(mix.entries.elements[1].order, entry.order)
    }

    // MARK: - Coding

    func testAServiceThisBuildDoesNotKnowSurvivesARoundTrip() throws {
        let json = """
        {"id":"p","createdAt":0,"name":{"value":"Mix","at":0},"notes":{"value":"","at":0},
         "cover":{"value":{"automatic":{}},"at":0},
         "entries":{"elements":[
           {"id":"e2","item":{"source":"jellyfin","kind":"song","id":"j1","title":"New"},"order":"a1","addedAt":0,"changedAt":0},
           {"id":"e1","item":{"source":"apple","kind":"song","id":"1","title":"Old"},"order":"a0","addedAt":0,"changedAt":0}
         ]}}
        """
        let mix = try JSONDecoder().decode(CuePlaylist.self, from: Data(json.utf8))
        XCTAssertEqual(mix.items.map(\.source.rawValue), ["apple", "jellyfin"])
        XCTAssertTrue(mix.entries.removed.isEmpty)

        let again = try CueLibraryCoding.decode(CuePlaylist.self, from: CueLibraryCoding.encode(mix))
        XCTAssertEqual(again, mix)
    }
}
