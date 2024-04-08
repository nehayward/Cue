import XCTest
@testable import SonosKit

final class IntegrationsAPITests: XCTestCase {
    let garageSonosIP = "192.168.4.50"
    let theaterIP = "192.168.4.144"
    let sonosService = SonosService()
    let sonosAPI = SonosAPI()

    func testGetPlayMode() async throws {
        let getPlaybackMode = await sonosAPI.playMode(garageSonosIP)
        XCTAssertEqual(getPlaybackMode, .normal)
    }

    func testSetPlayMode() async throws {
        await sonosAPI.setPlayMode(garageSonosIP, playMode: [.shuffle, .repeatOne])
        var playbackMode = await sonosAPI.playMode(garageSonosIP)
        XCTAssertEqual(playbackMode, [.repeatOne, .shuffle])

        await sonosAPI.setPlayMode(garageSonosIP, playMode: .shuffle)
        playbackMode = await sonosAPI.playMode(garageSonosIP)
        XCTAssertEqual(playbackMode, .shuffle)

        await sonosAPI.setPlayMode(garageSonosIP, playMode: [.shuffle, .repeatAll])
        playbackMode = await sonosAPI.playMode(garageSonosIP)
        XCTAssertEqual(playbackMode, [.shuffle, .repeatAll])
    }

    func testRemoveTrackFromQueue() async throws {
        await sonosAPI.removeTrackFromQueue(IP: garageSonosIP, index: 0)
    }

    func testGetGroupMute() async throws {
        let isMuted = await sonosAPI.getGroupMute(IP: garageSonosIP)
        print(isMuted)
    }

    func testDialogLevelFailing() async throws {
        await XCTAssertThrowsErrorAsync(
            try await sonosAPI.getDialogLevel(IP: garageSonosIP),
            SonosAPIError.failedLoading
        )
    }

    func testDialogLevel() async throws {
        try await sonosAPI.setDialogLevel(IP: theaterIP, enabled: false)
        let dialogLevelGetEnabledFalse = try await sonosAPI.getDialogLevel(IP: theaterIP)
        XCTAssertFalse(dialogLevelGetEnabledFalse)

        try await sonosAPI.setDialogLevel(IP: theaterIP, enabled: true)
        let dialogLevelGetEnabledTrue = try await sonosAPI.getDialogLevel(IP: theaterIP)
        XCTAssertTrue(dialogLevelGetEnabledTrue)
    }

    func testNightMode() async throws {
        try await sonosAPI.setNightMode(IP: theaterIP, enabled: false)
        let dialogLevelGetEnabledFalse = try await sonosAPI.getNightMode(IP: theaterIP)
        XCTAssertFalse(dialogLevelGetEnabledFalse)

        try await sonosAPI.setNightMode(IP: theaterIP, enabled: true)
        let dialogLevelGetEnabledTrue = try await sonosAPI.getNightMode(IP: theaterIP)
        XCTAssertTrue(dialogLevelGetEnabledTrue)
    }

    func testGetAudioInputFormat() async throws {
        let getAudioInputFormat = try await sonosAPI.getAudioInputFormat(IP: theaterIP)
        XCTAssertEqual(getAudioInputFormat, .multiChannelPCM)
    }
}
