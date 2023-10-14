import XCTest
@testable import SonosKit

final class IntegrationsTests: XCTestCase {
    let garageSonosIP = "192.168.4.50"
    let theaterIP = "192.168.4.144"
    let sonosService = SonosService()
    let api = SonosAPI()

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


    func testReorderQueue() async throws {
//        await sonosAPI.reorderQueue(IP: garageSonosIP)
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
}
