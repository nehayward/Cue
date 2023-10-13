import XCTest
@testable import SonosKit

final class IntegrationsTests: XCTestCase {
    let garageSonosIP = "192.168.4.50"
    let theaterIP = "192.168.4.144"
    let sonosService = SonosService()
    let sonosAPI = SonosAPI()

    func testQueue() async throws {
        await sonosService.queueSpotifyPlaylist(id: "7I1a94XGmUyXaGEYz3yghi", title: "Dua Lipa Discography", owner: "Dua Lipa", on: "192.168.4.49", group: GroupRoom(id: "", coordinatorID: "", rooms: [], coordinatorRoom: .garage))
    }

    func testSpotifyTrackQueue() async throws {
        await sonosService.queueSpotifyTrack(id: "1vYXt7VSjH9JIM5oRRo7vA", group: .garage)
    }

    func testGetQueue() async throws {
        let tracks = await sonosService.getQueue(ip: garageSonosIP)
        print(tracks)
    }

    func testRemoveTrackFromQueue() async throws {
        await sonosAPI.removeTrackFromQueue(IP: garageSonosIP, index: 0)
    }

    func testReorderQueue() async throws {
        await sonosAPI.reorderQueue(IP: garageSonosIP)
    }

    func testGetCurrentTransportActions() async throws {
        let availableActionsOptional = await sonosService.getCurrentTransportActions(ip: garageSonosIP)
        let availableActions = try XCTUnwrap(availableActionsOptional)
        XCTAssert(availableActions.contains(.play))
        print(availableActions)
    }

    func testGetGroup() async throws {
        do {
            let groups = try await sonosService.getGroups(with: "192")
            print(groups)
        }
        catch {
            print(error)
        }
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

func XCTAssertThrowsErrorAsync<T, R>(
    _ expression: @autoclosure () async throws -> T,
    _ errorThrown: @autoclosure () -> R,
    _ message: @autoclosure () -> String = "This method should fail",
    file: StaticString = #filePath,
    line: UInt = #line
) async where R: Comparable, R: Error  {
    do {
        let _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        XCTAssertEqual(error as? R, errorThrown())
    }
}
