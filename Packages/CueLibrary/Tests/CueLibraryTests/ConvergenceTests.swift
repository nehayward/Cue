import XCTest
@testable import CueLibrary

/// Three devices edit one playlist at random and now and then sync in
/// pairs; at the end, merging everyone in any order must give one playlist.
final class ConvergenceTests: XCTestCase {
    /// SplitMix64: the same run every time.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func song(_ n: Int) -> CueItem {
        CueItem(source: n.isMultiple(of: 2) ? .apple : .plex, kind: .song, id: "\(n)", title: "Song \(n)")
    }

    func testDevicesThatEditApartEndUpWithOnePlaylist() {
        for seed in 1...40 {
            var random = Seeded(state: UInt64(seed))
            let start = CuePlaylist(id: "p", name: "Mix", items: (0..<5).map(song), at: Date(timeIntervalSince1970: 0))
            var devices = [start, start, start]
            var clock: TimeInterval = 1
            var nextSong = 100

            for _ in 0..<150 {
                // Mostly whole seconds, so some edits land at the same moment.
                clock += Double(Int.random(in: 0...1, using: &random))
                let date = Date(timeIntervalSince1970: clock)
                let device = Int.random(in: 0..<devices.count, using: &random)
                var playlist = devices[device]
                let count = playlist.count
                switch Int.random(in: 0..<7, using: &random) {
                case 0, 1:
                    playlist.insert([song(nextSong)], at: Int.random(in: 0...count, using: &random), at: date)
                    nextSong += 1
                case 2 where count > 0:
                    let from = Int.random(in: 0..<count, using: &random)
                    playlist.move(fromOffsets: [from], toOffset: Int.random(in: 0...count, using: &random), at: date)
                case 3 where count > 0:
                    playlist.remove(atOffsets: [Int.random(in: 0..<count, using: &random)], at: date)
                case 4:
                    playlist.rename("Name \(Int.random(in: 0..<5, using: &random))", at: date)
                case 5 where count > 0:
                    let entry = playlist.entries.elements[Int.random(in: 0..<count, using: &random)]
                    playlist.replaceItem(entryID: entry.id, with: song(nextSong), at: date)
                    nextSong += 1
                default:
                    let other = Int.random(in: 0..<devices.count, using: &random)
                    let merged = playlist.merged(with: devices[other])
                    devices[other] = merged
                    playlist = merged
                }
                devices[device] = playlist
            }

            let forward = devices[0].merged(with: devices[1]).merged(with: devices[2])
            let backward = devices[2].merged(with: devices[1].merged(with: devices[0]))
            let shuffled = devices[1].merged(with: devices[2]).merged(with: devices[0])
            XCTAssertEqual(forward, backward, "seed \(seed)")
            XCTAssertEqual(forward, shuffled, "seed \(seed)")

            let entryIDs = forward.entries.elements.map(\.id)
            XCTAssertEqual(Set(entryIDs).count, entryIDs.count, "seed \(seed)")
            for id in entryIDs {
                XCTAssertNil(forward.entries.removed[id].flatMap { removedAt in
                    removedAt >= forward.entries.element(id: id)!.changedAt ? removedAt : nil
                }, "seed \(seed): a removed entry survived")
            }

            // Once everyone has everything, editing still works.
            var settled = forward
            settled.insert([song(-1)], at: settled.count / 2, at: Date(timeIntervalSince1970: clock + 1))
            XCTAssertEqual(settled.count, forward.count + 1, "seed \(seed)")
            let orders = settled.entries.elements.map(\.order)
            XCTAssertTrue(orders.allSatisfy(OrderKey.isValid), "seed \(seed)")
        }
    }
}
