import XCTest
import MusicSearchKit

final class IntegrationsTests: XCTestCase {
    let musicSearchService = MusicSearchService()

    func testGetID() async throws {
        await sonosService.load()
        print(sonosService.sonosDevices.first?.ipAddress)

        guard let garage = sonosService.sonosDevices.first(where: { device in
            device.name == "Theater"
        }) else { return }

        await sonosService.queue(song: "1673536432", on: garage)
    }


}
