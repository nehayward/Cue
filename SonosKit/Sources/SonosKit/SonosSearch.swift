import Foundation
import Network
import os

@Observable
public final class SonosSearch {
    var isSearching: Bool = true

    private var browser: NWBrowser?
    private let sonosBonjourServiceType = "_http._tcp"
    private var logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!,
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

    public var lastKnownIP: String = ""
    public var lastKnownState: String = ""

    public init() {
        
    }

    public func startBrowsing() {
        stopBrowsing()
        print("Search")
        let params = NWParameters()
        params.includePeerToPeer = true
        params.requiredInterfaceType = .wifi
        params.acceptLocalOnly = true
        params.allowFastOpen = true

        
        let browser = NWBrowser(for: .bonjour(type: sonosBonjourServiceType, domain: nil), using: params)
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

    func search() {
        print("Search")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        parameters.acceptLocalOnly = true
        parameters.allowFastOpen = true

        browser = nil
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sonos._tcp", domain: nil), using: parameters)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            self?.changeHandler(results)
        }
        browser?.stateUpdateHandler = { [weak self] in self?.stateHandler($0) }
        browser?.start(queue: .main)
    }

    func stop() {
        isSearching = false
        browser?.cancel()
        browser = nil
    }

    public func ssdp() {
        guard let multicastGroup = try? NWMulticastGroup(for: [ .hostPort(host: "239.255.255.250", port: 1900) ]) else {
            fatalError("Failed to create multicast group")
        }
        let connectionGroup = NWConnectionGroup(with: multicastGroup, using: .udp)
        connectionGroup.setReceiveHandler(maximumMessageSize: 16384, rejectOversizedMessages: true) { message, content, isComplete in
            print("Received message from \(String(describing: message.remoteEndpoint))")
            if let content = content, let message = String(data: content, encoding: .utf8) {
                print("Message: \(message)")
            }
        }
        connectionGroup.stateUpdateHandler = { newState in
            print("Group entered state \(String(describing: newState))")
        }
        connectionGroup.start(queue: .main)
        let searchString = "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n" +
            "MX: 1\r\n\r\n"
        let groupSendContent = Data(searchString.utf8)
//        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            connectionGroup.send(content: groupSendContent) { error in
                print("Send complete with error \(String(describing: error))")
            }
//        }
    }

    public func getFirstIP() async throws -> String {
        //        try? await Task.sleep(for: .seconds(4))
//        lastKnownIP = ""

        defer {
            isSearching = false
        }

        if !lastKnownIP.isEmpty {
            return lastKnownIP
        }

        isSearching = true
        startBrowsing()

        let task = Task {
            let date = Date.now

            while lastKnownIP.isEmpty {
                if permissionsDenied {
                    lastKnownIP = ""
                    throw SonosServiceError.permissionDenied
                }
                if Date.now > date.addingTimeInterval(20) {
                    lastKnownIP = ""
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
