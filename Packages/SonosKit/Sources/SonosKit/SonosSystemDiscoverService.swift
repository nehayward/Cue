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
    var isSearching: Bool = false
    var currentWakes: Set<String> = []
    var preferredHouseHold: String? {
        get {
            UserDefaults.standard.string(forKey: "clic.household")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "clic.household")
        }
    }

    @ObservationIgnored var sonosStorageIP = SonosStorageIP()
    @ObservationIgnored private var api = SonosAPI()
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private let sonosBonjourServiceType = "_sonos._tcp"
    @ObservationIgnored private var logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!,
                                        category: String(describing: SonosSystemDiscoverService.self))
    
    private let lock = OSAllocatedUnfairLock()
    private var permissionsDenied: Bool = false
    private var connections: [NWConnection?] = []
    private var allIPs: Set<String> = []

    var lastKnownIP: String = ""
    var lastKnownState: String = ""
    
    deinit {
        stopBrowsing()
        connections.forEach { $0?.cancel() }
        connections.removeAll()
    }

    @MainActor
    func getFirstIP(useCache: Bool) async throws -> String {
        if useCache && !sonosStorageIP.sonosIP.isEmpty {
            return sonosStorageIP.sonosIP
        }

        defer {
            isSearching = false
        }
        isSearching = true

        startBrowseAll()
        let task = Task {
            let startTime = Date.now
            try? await Task.sleep(for: .milliseconds(200))
            while allIPs.count != connections.count {
                if permissionsDenied {
                    throw SonosServiceError.permissionDenied
                }
                if Date.now > startTime.addingTimeInterval(8) {
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return allIPs
        }

        let ips = try await task.value
        let (ip, _) = try await withThrowingTaskGroup(of: (String, String).self, returning: (String, String).self) { taskGroup in
            for ip in ips {
                taskGroup.addTask { [weak self] in
                    guard let self = self else { return ("", "") }
                    let id = await api.getHouseHoldID(for: ip)
                    return (ip, id)
                }
            }

            while let (ip, id) = try await taskGroup.next() {
                if let preferredHouseHold = preferredHouseHold, preferredHouseHold != id {
                    continue
                }
                sonosStorageIP.sonosIP = ip
                preferredHouseHold = id
                return (ip, id)
            }
            
            guard let ip = ips.first else {
                return ("", "")
            }

            // MARK: Preferred not found
            return (ip, "")
        }

        if ip.isEmpty {
            throw SonosServiceError.sonosSystemNotFound
        }

        return ip
    }

    func startQuickBrowse() {
        stopBrowsing()
        print("Search")
        let params = NWParameters()
        params.requiredInterfaceType = .wifi
        params.allowFastOpen = true

        let browser = NWBrowser(for: .bonjour(type: sonosBonjourServiceType, domain: nil), using: params)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] services, changed in
            guard let self else { return }
            changeHandler(services, changed)
        }

        browser.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            stateHandler(newState)
        }

        browser.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        // Cancel all connections to prevent leaks
        connections.forEach { $0?.cancel() }
    }


    @MainActor
    func getAllIPs() async throws -> [String] {
        startBrowseAll()
        
        defer {
            stopBrowsing()
        }
        
        let startTime = Date.now
        try? await Task.sleep(for: .milliseconds(200))
        
        while allIPs.count != connections.count {
            if permissionsDenied {
                throw SonosServiceError.permissionDenied
            }
            if Date.now > startTime.addingTimeInterval(3) {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        return Array(allIPs)
    }

    func startBrowseAll() {
        stopBrowsing()
        allIPs.removeAll()
        // Cancel all existing connections before removing them to prevent leaks
        connections.forEach { $0?.cancel() }
        connections.removeAll()
        
        let params = NWParameters()
        params.requiredInterfaceType = .wifi
        params.allowFastOpen = true

        let browser = NWBrowser(for: .bonjour(type: sonosBonjourServiceType, domain: nil), using: params)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] services, changed in
            guard let self else { return }
            changeHandlerAll(services, changed)
        }

        browser.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            stateHandler(newState)
        }

        browser.start(queue: .main)
    }

    private func changeHandler(_ services: Set<NWBrowser.Result>, _ changes: Set<NWBrowser.Result.Change>) {
        defer {
            stopBrowsing()
        }

        for service in services {
            var netConnection: NWConnection?

            if case let .service(name, type, domain, interface) = service.endpoint {
                netConnection = NWConnection(to: .service(name: name, type: type, domain: domain, interface: interface), using: .tcp)
                netConnection?.stateUpdateHandler = { [weak self, weak netConnection] newState in
                    switch newState {
                    case .ready:
                        guard let currentPath = netConnection?.currentPath,
                              let endpoint = currentPath.remoteEndpoint else { return }

                        if case let .hostPort(host, _) = endpoint, let ip = host.debugDescription.components(separatedBy: "%").first {
                            self?.lastKnownIP = ip
                            return
                        }

                    default:
                        break
                    }
                }
            }
            netConnection?.start(queue: .global())
            connections.append(netConnection)
        }
    }

    private func changeHandlerAll(_ services: Set<NWBrowser.Result>, _ changes: Set<NWBrowser.Result.Change>) {
        for service in services {
            var netConnection: NWConnection?

            if case let .service(name, type, domain, interface) = service.endpoint {
                netConnection = NWConnection(to: .service(name: name, type: type, domain: domain, interface: interface), using: .tcp)
                netConnection?.stateUpdateHandler = { [weak self, weak netConnection] newState in
                    switch newState {
                    case .ready:
                        guard let self = self,
                              let currentPath = netConnection?.currentPath,
                              let endpoint = currentPath.remoteEndpoint else { return }

                        if case let .hostPort(host, _) = endpoint, let ip = host.debugDescription.components(separatedBy: "%").first {
                            lock.withLock {
                                self.allIPs.insert(ip)
                            }
                        }
                    default:
                        break
                    }
                }
            }
            netConnection?.start(queue: .global())
            connections.append(netConnection)
        }
    }

    private func stateHandler(_ newState: NWBrowser.State) {
        lastKnownState = newState.debugDescription

        switch newState {
        case .ready:
            logger.trace("Browser ready. Starting browsing...")
        case let .failed(error):
            logger.trace("Browser failed with error: \(error)")
            self.browser?.cancel()
            self.startQuickBrowse()
        case let .waiting(error):
            print(error.errorCode)
            if let description = error.errorUserInfo["NSDescription"] as? String, description == "PolicyDenied" {
                logger.trace("Browser failed waiting error: \(error)")
                permissionsDenied = true
            }
        case .cancelled:
            lastKnownState = "Cancelled"
        default:
            break
        }
    }

    func sendWakeOnLANPacket(macAddress: String, broadcastAddress: String = "255.255.255.255") {
        if currentWakes.contains(macAddress) { return }

        currentWakes.insert(macAddress)
        // Convert the MAC address to data
        let macData = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard macData.count == 6 else {
            print("Invalid MAC address")
            return
        }

        // Create the magic packet
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macData)
        }

        // Create a UDP connection to the broadcast address
        let connection = NWConnection(host: NWEndpoint.Host(broadcastAddress), port: 9, using: .udp)

        // Send the magic packet
        connection.start(queue: .global())
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("Failed to send magic packet: \(error)")
            } else {
                print("Magic packet sent successfully")
            }
            connection.cancel()
        })
    }
}
