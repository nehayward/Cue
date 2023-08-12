import XCTest
import SonosKit

final class IntegrationsTests: XCTestCase {
    let sonosService = SonosService()

    func testQueue() async throws {
        await sonosService.queueSpotifyPlaylist(id: "7I1a94XGmUyXaGEYz3yghi", title: "Dua Lipa Discography", owner: "Dua Lipa", on: "192.168.4.49")
    }

    
}
