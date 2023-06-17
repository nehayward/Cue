import XCTest
import SonosKit

final class IntegrationsTests: XCTestCase {
    let sonosService = SonosService()

    func testQueue() async throws {
        await sonosService.load()
        print(sonosService.sonosDevices.first?.ipAddress)

        guard let garage = sonosService.sonosDevices.first(where: { device in
            device.name == "Theater"
        }) else { return }

        await sonosService.queue(song: "1673536432", on: garage)
    }

    
}
