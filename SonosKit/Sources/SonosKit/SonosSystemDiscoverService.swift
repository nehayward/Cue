import CloudStorage
import Foundation
import Network
import os


extension NWBrowser.State {
    var debugDescription: String {
        switch self {
        case .cancelled:
            return "Cancelled"
        case .failed(let error):
            return "Failed: \(error)"
        case .ready:
            return "Ready"
        case .setup:
            return "Setup"
        case .waiting(let error):
            return "Waiting: \(error)"
        @unknown default:
            return "Unknown"
        }
    }
}

class SonosStorageIP: ObservableObject {
    @CloudStorage("sonos_ip") var sonosIP = ""
}

@Observable
final class SonosSystemDiscoverService {
    var isSearching: Bool = true

    @ObservationIgnored private var sonosStorageIP = SonosStorageIP()
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private let sonosBonjourServiceType = "_sonos._tcp"
    @ObservationIgnored private var logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!,
                                        category: String(describing: SonosSystemDiscoverService.self))

    private var permissionsDenied: Bool = false

//    var lastKnownIP: String {
//        get {
//            UserDefaults.standard.string(forKey: "sonos.ip") ?? ""
//        }
//        set {
//            UserDefaults.standard.set(newValue, forKey: "sonos.ip")
//        }
//    }

    var lastKnownIP: String = ""
    var lastKnownState: String = ""

    func startBrowsing() {
        stopBrowsing()
        print("Search")
        let params = NWParameters()
        params.includePeerToPeer = true
        params.requiredInterfaceType = .wifi
        params.acceptLocalOnly = true
        params.allowFastOpen = true

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: sonosBonjourServiceType, domain: nil), using: params)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, changed in
            guard let self else { return }
            print("Browse results")
            print(results)
            print("CHANGED")
            print(changed)
            self.changeHandler(results)
        }

        browser.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            os_log("[browser] %@", newState.debugDescription)
//            print(newState.debugDescription)
            lastKnownState = newState.debugDescription
            switch newState {
            case .cancelled:
                break
            case .failed:
                print("Failed")
                os_log("[browser] restarting")
                self.browser?.cancel()
                self.startBrowsing()
            case .ready:
                break
            case .setup:
                break
            case .waiting(let error):
                print(error)
            @unknown default:
                break
            }
        }

        browser.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        
    }
    //
    //    func search() {
    //        print("Search")
    //        let parameters = NWParameters()
    //        parameters.includePeerToPeer = true
    //        parameters.acceptLocalOnly = true
    //        parameters.allowFastOpen = true
    //
    //        browser = nil
    //        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sonos._tcp", domain: nil), using: parameters)
    //        browser?.browseResultsChangedHandler = { [weak self] results, _ in
    //            self?.changeHandler(results)
    //        }
    //        browser?.stateUpdateHandler = { [weak self] in self?.stateHandler($0) }
    //        browser?.start(queue: .main)
    //    }
    //
    //    func stop() {
    //        isSearching = false
    //        browser?.cancel()
    //        browser = nil
    //    }

    @MainActor
    func getFirstIP(useCache: Bool) async throws -> String {
        //        try? await Task.sleep(for: .seconds(4))
//        lastKnownIP = ""

        defer {
            isSearching = false
        }
        isSearching = true

        if useCache && !sonosStorageIP.sonosIP.isEmpty {
            return sonosStorageIP.sonosIP
        }

        lastKnownIP = ""
        startBrowsing()
        let task = Task {
            let date = Date.now
            while lastKnownIP.isEmpty {
                if permissionsDenied {
                    throw SonosServiceError.permissionDenied
                }
                if Date.now > date.addingTimeInterval(5) {
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }

            if lastKnownIP.isEmpty {
                throw SonosServiceError.sonosSystemNotFound
            }

            sonosStorageIP.sonosIP = lastKnownIP
            return lastKnownIP
        }
        let ip = try await task.value
        return ip
    }

    private func changeHandler(_ results: Set<NWBrowser.Result>) {
        defer {
            stopBrowsing()
        }

        guard let firstResult = results.first else {
            logger.error("Nothing found")
            return
        }
        guard case let .bonjour(txtRecord) = firstResult.metadata, let location = txtRecord.dictionary["location"] else {
            logger.error("No TXTRecord found")
            print("No Record")
            return
        }

        print("Found Sonos Device: \(location)")
        logger.trace("Found Sonos Device: \(location,  align: .right(columns: 10))")
        let components = URLComponents(string: location)
        guard let ip = components?.host else {
            return
        }

        print("Found IP for Sonos device, \(ip)")
        logger.trace("Found IP for Sonos device, \(ip,  align: .right(columns: 10))")
        lastKnownIP = ip
    }

    private func stateHandler(_ newState: NWBrowser.State) {
        switch newState {
        case .ready:
            lastKnownState = "Ready"
            print("Ready")
            logger.trace("Browser ready. Starting browsing...")
        case let .failed(error):
            lastKnownState = "Failed"
            logger.trace("Browser failed with error: \(error)")
            stopBrowsing()
        case let .waiting(error):
            print("Waiting")
            lastKnownState = "Waiting"
            logger.trace("Browser failed waiting error: \(error)")
            permissionsDenied = true
        case .cancelled:
            lastKnownState = "Cancelled"
            print("Browser Cancelled")
            print(newState)
        default:
            print("NewState:", newState)
            break
        }
    }
}
