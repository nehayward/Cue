import Foundation
import Network
import os

/// Errors that can occur during Sonos system discovery
enum SonosDiscoveryError: Error {
    case permissionDenied
    case sonosSystemNotFound
    case networkError(Error)
    case timeout
}

/// Service to discover Sonos systems on the local network
final class SonosSystemDiscoveryService {
    private let sonosServiceType = "_sonos._tcp"
    private let lock = OSAllocatedUnfairLock()
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []
    private var discoveredIPs: Set<String> = []
    private var isSearching = false
    private var permissionsDenied = false
    private var currentWakeRequests: Set<String> = []
    
    /// The preferred household ID stored in user defaults
    var preferredHousehold: String? {
        get { UserDefaults.standard.string(forKey: "clic.household") }
        set { UserDefaults.standard.set(newValue, forKey: "clic.household") }
    }
    
    // MARK: - Public Methods
    
    /// Discover the first Sonos device on the network
    func discoverFirstDevice(useCache: Bool) async throws -> String {
        if useCache, !discoveredIPs.isEmpty {
            return discoveredIPs.first ?? ""
        }
        let discoveredIPs = try await discoverDevices(timeout: 15)
        return discoveredIPs.first ?? ""
    }
    
    /// Discover all Sonos devices on the network
    func discoverAllDevices() async throws -> [String] {
        return Array(try await discoverDevices(timeout: 5))
    }
    
    /// Sends a Wake-on-LAN packet to the specified MAC address
    func sendWakeOnLAN(macAddress: String, broadcastAddress: String = "255.255.255.255") async {
        guard !currentWakeRequests.contains(macAddress) else { return }
        currentWakeRequests.insert(macAddress)
        
        guard let packet = try? createMagicPacket(macAddress: macAddress) else { return }
        await sendUDPPacket(packet, to: broadcastAddress)
    }
    
    // MARK: - Private Methods
    
    private func discoverDevices(timeout: TimeInterval) async throws -> Set<String> {
        try lock.withLock {
            guard !isSearching else {
                throw SonosDiscoveryError.timeout
            }
            isSearching = true
            discoveredIPs.removeAll()
        }
        
        startBrowsing()
        
        try await withTimeout(seconds: timeout) { [weak self] in
            guard let self else { return }
            
            while self.lock.withLock({ self.discoveredIPs.isEmpty }) {
                if self.lock.withLock({ self.permissionsDenied }) {
                    throw SonosDiscoveryError.permissionDenied
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        
        return lock.withLock { discoveredIPs }
    }
    
    private func startBrowsing() {
        stopBrowsing()
        
        let params = NWParameters()
        params.requiredInterfaceType = .wifi
        params.allowFastOpen = true
        
        let browser = NWBrowser(for: .bonjour(type: sonosServiceType, domain: nil), using: params)
        self.browser = browser
        
        browser.browseResultsChangedHandler = { [weak self] services, _ in
            self?.processDiscoveredServices(services)
        }
        
        browser.stateUpdateHandler = { [weak self] state in
            self?.handleBrowserState(state)
        }
        
        browser.start(queue: .global())
    }
    
    private func stopBrowsing() {
        browser?.cancel()
        browser = nil
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        isSearching = false
    }
    
    private func processDiscoveredServices(_ services: Set<NWBrowser.Result>) {
        lock.withLock {
            for service in services {
                guard case let .service(name, type, domain, interface) = service.endpoint else { continue }
                
                let connection = NWConnection(to: .service(name: name, type: type, domain: domain, interface: interface), using: .tcp)
                connection.stateUpdateHandler = { [weak self] state in
                    if case .ready = state {
                        self?.processConnectionReady(connection)
                    }
                }
                
                connection.start(queue: .global())
                activeConnections.append(connection)
            }
        }
    }
    
    private func processConnectionReady(_ connection: NWConnection) {
        guard let endpoint = connection.currentPath?.remoteEndpoint,
              case let .hostPort(host, _) = endpoint,
              let ip = host.debugDescription.components(separatedBy: "%").first else { return }
        
        lock.lock()
        defer { lock.unlock() }
        discoveredIPs.insert(ip)
    }
    
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            break
        case .failed:
            startBrowsing()
        case .waiting(let error):
            if (error.errorUserInfo["NSDescription"] as? String) == "PolicyDenied" {
                lock.withLock {
                    permissionsDenied = true
                }
            }
        default:
            break
        }
    }
    
    private func createMagicPacket(macAddress: String) throws -> Data {
        let macBytes = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard macBytes.count == 6 else { throw SonosDiscoveryError.networkError(NSError(domain: "Invalid MAC Address", code: -1)) }
        
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }
    
    private func sendUDPPacket(_ packet: Data, to address: String) async {
        let connection = NWConnection(host: NWEndpoint.Host(address), port: 9, using: .udp)
        connection.start(queue: .global())
        
        await withCheckedContinuation { continuation in
            connection.send(content: packet, completion: .contentProcessed { _ in
                connection.cancel()
                continuation.resume()
            })
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw SonosDiscoveryError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
