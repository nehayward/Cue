import XCTest
@testable import MusicSearchKit

final class ApplePlaylistDeletionTests: XCTestCase {
    private typealias Playlist = ApplePlaylistDeletion.MusicPlaylist

    private let roadTrip = Playlist(name: "Road Trip", persistentID: "AAAAAAAAAAAAAAAA", kind: .plain)
    private let gym = Playlist(name: "Gym", persistentID: "BBBBBBBBBBBBBBBB", kind: .plain)

    private func choose(
        _ name: String,
        linked: String? = nil,
        in playlists: [Playlist]
    ) -> ApplePlaylistDeletion.Choice {
        ApplePlaylistDeletion.choose(name: name, linkedPersistentID: linked, in: playlists)
    }

    func testALinkedPlaylistIsChosenExactly() {
        XCTAssertEqual(
            choose("Road Trip", linked: roadTrip.persistentID, in: [gym, roadTrip]),
            .exact(persistentID: roadTrip.persistentID)
        )
    }

    func testAnUnlinkedPlaylistGoesOnlyIfEmpty() {
        XCTAssertEqual(
            choose("Road Trip", in: [gym, roadTrip]),
            .onlyIfEmpty(persistentID: roadTrip.persistentID)
        )
    }

    func testTwoOfOneNameAreRefusedEvenWithALink() {
        let other = Playlist(name: "Road Trip", persistentID: "CCCCCCCCCCCCCCCC", kind: .plain)
        XCTAssertEqual(
            choose("Road Trip", linked: roadTrip.persistentID, in: [roadTrip, other]),
            .refuse(.sameName(count: 2))
        )
        XCTAssertEqual(choose("Road Trip", in: [roadTrip, other]), .refuse(.sameName(count: 2)))
    }

    func testNamesDifferingByCaseOrAccentCountAsTheSame() {
        let upper = Playlist(name: "ROAD TRIP", persistentID: "CCCCCCCCCCCCCCCC", kind: .plain)
        XCTAssertEqual(choose("Road Trip", in: [roadTrip, upper]), .refuse(.sameName(count: 2)))

        let cafe = Playlist(name: "Cafe", persistentID: "DDDDDDDDDDDDDDDD", kind: .plain)
        let café = Playlist(name: "Café", persistentID: "EEEEEEEEEEEEEEEE", kind: .plain)
        XCTAssertEqual(choose("Cafe", linked: cafe.persistentID, in: [cafe, café]), .refuse(.sameName(count: 2)))
    }

    func testAFolderOrSubscriptionOfTheSameNameCounts() {
        let folder = Playlist(name: "Road Trip", persistentID: "CCCCCCCCCCCCCCCC", kind: .folder)
        XCTAssertEqual(choose("Road Trip", in: [roadTrip, folder]), .refuse(.sameName(count: 2)))

        let added = Playlist(name: "Road Trip", persistentID: "DDDDDDDDDDDDDDDD", kind: .subscription)
        XCTAssertEqual(
            choose("Road Trip", linked: roadTrip.persistentID, in: [roadTrip, added]),
            .refuse(.sameName(count: 2))
        )
    }

    func testOnlyAPlainPlaylistMayGo() {
        for kind: Playlist.Kind in [.smart, .genius, .special, .folder, .subscription, .other] {
            let playlist = Playlist(name: "Road Trip", persistentID: "AAAAAAAAAAAAAAAA", kind: kind)
            XCTAssertEqual(choose("Road Trip", in: [playlist]), .refuse(.wrongKind(kind)))
            XCTAssertEqual(
                choose("Road Trip", linked: playlist.persistentID, in: [playlist]),
                .refuse(.wrongKind(kind))
            )
        }
    }

    func testNothingInMusicIsRefused() {
        XCTAssertEqual(choose("Road Trip", in: [gym]), .refuse(.notInMusic))
        XCTAssertEqual(choose("Road Trip", linked: roadTrip.persistentID, in: [gym]), .refuse(.notInMusic))
        XCTAssertEqual(choose("Road Trip", in: []), .refuse(.notInMusic))
    }

    /// A link to a playlist Music calls something else is never followed,
    /// even with the name Cue shows free in Music.
    func testALinkToAnotherNameIsRefused() {
        XCTAssertEqual(
            choose("Road Trip", linked: gym.persistentID, in: [gym]),
            .refuse(.nameDiffers(inMusic: "Gym"))
        )
        // By a link that disagrees with the one playlist of the name, too.
        XCTAssertEqual(
            choose("Road Trip", linked: gym.persistentID, in: [gym, roadTrip]),
            .refuse(.nameDiffers(inMusic: "Gym"))
        )
    }

    func testAnUnlinkedNameDifferingByCaseIsRefused() {
        let lower = Playlist(name: "road trip", persistentID: "CCCCCCCCCCCCCCCC", kind: .plain)
        XCTAssertEqual(choose("Road Trip", in: [lower]), .refuse(.nameDiffers(inMusic: "road trip")))
    }

    func testAPersistentIDFromAMusicKitID() {
        // Pairs read from a real library (both signs).
        XCTAssertEqual(ApplePlaylistDeletion.persistentID(fromMusicKitID: "3444766541532760246"), "2FCE44EB1A3608B6")
        XCTAssertEqual(ApplePlaylistDeletion.persistentID(fromMusicKitID: "-3383289347600089593"), "D10C244387EEFE07")
        // Leading zeros are kept: Music always gives 16 digits.
        XCTAssertEqual(ApplePlaylistDeletion.persistentID(fromMusicKitID: "255"), "00000000000000FF")
    }

    func testOtherKindsOfIDHaveNoPersistentID() {
        XCTAssertNil(ApplePlaylistDeletion.persistentID(fromMusicKitID: "p.9R3kCbRkb1"))
        XCTAssertNil(ApplePlaylistDeletion.persistentID(fromMusicKitID: "pl.u-zV79tqNKqY"))
        XCTAssertNil(ApplePlaylistDeletion.persistentID(fromMusicKitID: ""))
    }
}
