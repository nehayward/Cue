import Foundation
import Network
import os


final class SonosSystemDiscoverService {
    var sonosIP: String = ""
    
    private var browser: NWBrowser?
    private let sonosServiceType = "_sonos._tcp"
    private lazy var logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: SonosSystemDiscoverService.self))

    func search() {
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: sonosServiceType, domain: "local."), using: .applicationService)
        browser?.browseResultsChangedHandler = changeHandler
        browser?.stateUpdateHandler = stateHandler
        browser?.start(queue: .global())
    }

    func stop() {
        browser?.cancel()
    }

    func getFirstIP() async throws -> String {
        guard sonosIP.isEmpty else {
            return sonosIP
        }

        let task = Task {
            search()
            let date = Date.now
            while sonosIP.isEmpty {
                if Date.now > date.addingTimeInterval(3) {
                    break
                }
                try await Task.sleep(nanoseconds: (UInt64(0.2) * 1_000_000_000))
            }
            return sonosIP
        }

        return try await task.value
    }

    private func changeHandler(_ newResults: Set<NWBrowser.Result>, _ changes: Set<NWBrowser.Result.Change>) {
        guard let firstResult = newResults.first else {
            logger.error("Nothing found")
            return
        }
        guard case let .bonjour(txtRecord) = firstResult.metadata, let location = txtRecord.dictionary["location"] else {
            logger.error("No TXTRecord found")
            return
        }

        logger.trace("Found location for Sonos device, \(location,  align: .right(columns: 10))")
        let components = URLComponents(string: location)
        guard let ip = components?.host else {
            return
        }
        logger.trace("Found IP for Sonos device, \(ip,  align: .right(columns: 10))")
        sonosIP = ip
        stop()
    }

    private func stateHandler(_ newState: NWBrowser.State) {
        switch newState {
        case .ready:
            logger.trace("Browser ready. Starting browsing...")
        case let .failed(error):
            logger.trace("Browser failed with error: \(error)")
        default:
            break
        }
    }
}
