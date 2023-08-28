import XCTest
import SonosKit

final class IntegrationsTests: XCTestCase {
    let garageSonosIP = "192.168.4.50"
    let sonosService = SonosService()

    func testQueue() async throws {
        await sonosService.queueSpotifyPlaylist(id: "7I1a94XGmUyXaGEYz3yghi", title: "Dua Lipa Discography", owner: "Dua Lipa", on: "192.168.4.49", group: GroupRoom(id: "", coordinatorID: "", rooms: []))
    }

    func testGetQueue() async throws {
        let tracks = await sonosService.getQueue(ip: garageSonosIP)
        print(tracks)
    }

    func testGetCurrentTransportActions() async throws {
        let availableActions = await sonosService.getCurrentTransportActions(ip: garageSonosIP)
        XCTAssert(availableActions.contains(.play))
        print(availableActions)
    }
}
