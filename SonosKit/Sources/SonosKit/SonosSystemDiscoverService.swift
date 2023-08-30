import Foundation
import Network
import os

final class SonosSystemDiscoverService {
    var isSearching: Bool = true

    private var browser: NWBrowser?
    private let sonosServiceType = "_sonos._tcp"
    private lazy var logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!,
                                             category: String(describing: SonosSystemDiscoverService.self))

    private var permissionsDenied: Bool = false

    var lastKnownIP: String {
        get {
            UserDefaults.standard.string(forKey: "sonos.ip") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "sonos.ip")
        }
    }

    init() { }

    func search() {
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: sonosServiceType, domain: "local."), using: .applicationService)
        browser?.browseResultsChangedHandler = changeHandler
        browser?.stateUpdateHandler = stateHandler
        browser?.start(queue: .global())
    }

    func stop() {
        isSearching = false
        browser?.cancel()
    }

    func getFirstIP() async throws -> String {
        defer {
            isSearching = false
        }

        if !lastKnownIP.isEmpty {
            return lastKnownIP
        }

        isSearching = true

        let task = Task {
            search()
            let date = Date.now
            while lastKnownIP.isEmpty {
                if permissionsDenied {
                    lastKnownIP = ""
                    throw SonosServiceError.permissionDenied
                }
                if Date.now > date.addingTimeInterval(4) {
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if lastKnownIP.isEmpty {
                throw SonosServiceError.sonosSystemNotFound
            }
            return lastKnownIP
        }
        let ip = try await task.value
        stop()
        return ip
    }

    private func changeHandler(_ newResults: Set<NWBrowser.Result>, _ changes: Set<NWBrowser.Result.Change>) {
        defer {
            stop()
        }

        guard let firstResult = newResults.first else {
            logger.error("Nothing found")
            return
        }
        guard case let .bonjour(txtRecord) = firstResult.metadata, let location = txtRecord.dictionary["location"] else {
            logger.error("No TXTRecord found")
            return
        }

#if os(watchOS)
        print("Found Sonos Device: \(location)")
#endif
        logger.trace("Found Sonos Device: \(location,  align: .right(columns: 10))")
        let components = URLComponents(string: location)
        guard let ip = components?.host else {
            return
        }

#if os(watchOS)
        print("Found IP for Sonos device, \(ip)")
#endif
        logger.trace("Found IP for Sonos device, \(ip,  align: .right(columns: 10))")
        lastKnownIP = ip
    }

    private func stateHandler(_ newState: NWBrowser.State) {
        switch newState {
        case .ready:
            logger.trace("Browser ready. Starting browsing...")
        case let .failed(error):
            logger.trace("Browser failed with error: \(error)")
            permissionsDenied = true
        case let .waiting(error):
            logger.trace("Browser failed waiting error: \(error)")
            permissionsDenied = true
        default:
            print("NewState:", newState)
            break
        }
    }
}
