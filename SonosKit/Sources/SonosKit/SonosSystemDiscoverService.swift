import Foundation
import Network
import os

final class SonosSystemDiscoverService {
    var sonosIP: String = ""
    
    private var browser: NWBrowser?
    private let sonosServiceType = "_sonos._tcp"
    private lazy var logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!, 
                                             category: String(describing: SonosSystemDiscoverService.self))

    private let pathMonitor: NWPathMonitor
    private let backgroudQueue = DispatchQueue.global(qos: .background)

    private var permissionsDenied: Bool = false

    var lastKnownIP: String? {
        get {
            UserDefaults.standard.string(forKey: "sonos.ip")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "sonos.ip")
        }
    }

    init() {
        pathMonitor = NWPathMonitor()
        pathMonitor.start(queue: backgroudQueue)
    }

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
        if pathMonitor.currentPath.isExpensive {
            sonosIP = ""
            throw SonosServiceError.noWifi
        }

        if let lastKnownIP, !lastKnownIP.isEmpty {
            return lastKnownIP
        }

        guard sonosIP.isEmpty else {
            return sonosIP
        }

        let task = Task {
            search()
            let date = Date.now
            while sonosIP.isEmpty {
                if permissionsDenied {
                    throw SonosServiceError.permissionDenied
                }
                if Date.now > date.addingTimeInterval(5) {
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            lastKnownIP = sonosIP

            if sonosIP.isEmpty {
                throw SonosServiceError.sonosSystemNotFound
            }
            return sonosIP
        }
        stop()

        let ip = try await task.value
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
        sonosIP = ip
    }

    private func stateHandler(_ newState: NWBrowser.State) {
        switch newState {
        case .ready:
            logger.trace("Browser ready. Starting browsing...")
        case let .failed(error):
            logger.trace("Browser failed with error: \(error)")
        case let .waiting(error):
            logger.trace("Browser failed waiting error: \(error)")
            permissionsDenied = true
        default:
            print("NewState:", newState)
            break
        }
    }
}
