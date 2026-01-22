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
    var isCellular: Bool = false
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
    @ObservationIgnored private let cellularMonitor = NWPathMonitor()
    @ObservationIgnored private var cellularUpdateTask: Task<Void, Never>?

    private let lock = OSAllocatedUnfairLock()
    private var permissionsDenied: Bool = false
    private var connections: [NWConnection?] = []
    private var allIPs: Set<String> = []
    private var householdIDCache: [String: (id: String, timestamp: Date)] = [:] // IP -> (HouseholdID, Timestamp)

    var lastKnownIP: String = ""
    var lastKnownState: String = ""

    init() {
        cellularMonitor.pathUpdateHandler = { [weak self] path in
            self?.cellularUpdateTask?.cancel()
            self?.cellularUpdateTask = Task { @MainActor [weak self] in
                self?.isCellular = path.usesInterfaceType(.cellular)
            }
        }
        cellularMonitor.start(queue: DispatchQueue(label: "CellularMonitor"))
    }

    deinit {
        stopBrowsing()
        cellularUpdateTask?.cancel()
        cellularMonitor.cancel()
        lock.withLock {
            connections.forEach { $0?.cancel() }
            connections.removeAll()
        }
    }

    /// Gets household ID with caching and fast timeout (2 seconds max)
    private func getHouseholdIDWithCache(for ip: String) async -> String {
        // Check cache first (valid for 5 minutes)
        if let cached = lock.withLock({ householdIDCache[ip] }),
           Date.now.timeIntervalSince(cached.timestamp) < 300 {
            return cached.id
        }

        // Fetch with 2-second timeout
        let householdID = await withTaskGroup(of: String.self, returning: String.self) { group in
            group.addTask { [weak self] in
                guard let self else { return "" }
                return await self.api.getHouseHoldID(for: ip)
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return "" // Timeout marker
            }

            // Return first result (either the API call or timeout)
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return ""
        }

        // Cache the result if valid
        if !householdID.isEmpty {
            lock.withLock {
                householdIDCache[ip] = (householdID, Date.now)
            }
        }

        return householdID
    }

    @MainActor
    func getFirstIP(useCache: Bool) async throws -> String {
        if useCache && !sonosStorageIP.sonosIP.isEmpty {
            return sonosStorageIP.sonosIP
        }

        // Skip discovery on cellular - Sonos devices are only reachable on local network
        if isCellular {
            throw SonosServiceError.sonosSystemNotFound
        }

        defer {
            isSearching = false
            stopBrowsing()
        }
        isSearching = true

        return try await performDiscovery()
    }

    /// Performs the actual device discovery
    private func performDiscovery() async throws -> String {
        startBrowseAll()

        // Streaming discovery: check IPs as they arrive
        return try await withThrowingTaskGroup(of: (String, String).self, returning: String.self) { taskGroup in
            var processedIPs = Set<String>()
            var fallbackIP: String?
            let startTime = Date.now
            let maxDiscoveryTime: TimeInterval = 10 

            // Minimal initial delay to let Bonjour browser start
            try? await Task.sleep(for: .milliseconds(100))

            while true {
                // Check for timeout
                if Date.now > startTime.addingTimeInterval(maxDiscoveryTime) {
                    break
                }

                // Check for permission denied
                if permissionsDenied {
                    taskGroup.cancelAll()
                    throw SonosServiceError.permissionDenied
                }

                // Get newly discovered IPs
                let currentIPs = lock.withLock { allIPs }
                let newIPs = currentIPs.subtracting(processedIPs)

                // Start checking household IDs for new IPs immediately
                for ip in newIPs {
                    processedIPs.insert(ip)
                    let ipCopy = ip // Capture for task
                    taskGroup.addTask { [weak self] in
                        guard let self else { return ("", "") }
                        let id = await self.getHouseholdIDWithCache(for: ipCopy)
                        return (ipCopy, id)
                    }
                }

                // Check if any household ID checks have completed (non-blocking)
                if let result = try? await taskGroup.next() {
                    let (resultIP, householdID) = result
                    guard !resultIP.isEmpty else { continue }

                    // Store first valid IP as fallback
                    if fallbackIP == nil && !householdID.isEmpty {
                        fallbackIP = resultIP
                    }

                    // If preferred household matches, return immediately
                    if let preferredHouseHold = preferredHouseHold {
                        if householdID == preferredHouseHold {
                            logger.trace("Found preferred household: \(householdID) at IP: \(resultIP)")
                            sonosStorageIP.sonosIP = resultIP
                            taskGroup.cancelAll()
                            return resultIP
                        }
                    } else if !householdID.isEmpty {
                        // No preference set - use first device found
                        logger.trace("No preferred household, using first found: \(householdID) at IP: \(resultIP)")
                        sonosStorageIP.sonosIP = resultIP
                        preferredHouseHold = householdID
                        taskGroup.cancelAll()
                        return resultIP
                    }
                }

                // If all IPs have been processed and checked, we can exit early
                let totalConnections = lock.withLock { connections.count }
                if processedIPs.count >= totalConnections && processedIPs.count > 0 {
                    // Give a bit more time in case more devices appear
                    if Date.now > startTime.addingTimeInterval(0.5) {
                        break
                    }
                }

                try? await Task.sleep(for: .milliseconds(25))
            }

            // Drain remaining results
            while let (resultIP, householdID) = try? await taskGroup.next() {
                if !resultIP.isEmpty && !householdID.isEmpty {
                    fallbackIP = resultIP
                    break
                }
            }

            taskGroup.cancelAll()

            // Return fallback IP if we found any device
            if let fallbackIP = fallbackIP {
                logger.trace("Returning fallback IP: \(fallbackIP)")
                sonosStorageIP.sonosIP = fallbackIP
                return fallbackIP
            }

            throw SonosServiceError.sonosSystemNotFound
        }
    }

    func startQuickBrowse() {
        stopBrowsing()
        print("Search")
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        params.allowFastOpen = true
        params.multipathServiceType = .handover
        params.serviceClass = .responsiveData

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
        lock.withLock {
            connections.forEach { $0?.cancel() }
        }
    }


    @MainActor
    func getAllIPs() async throws -> [String] {
        // Skip discovery on cellular - Sonos devices are only reachable on local network
        if isCellular {
            return []
        }

        startBrowseAll()

        defer {
            stopBrowsing()
        }

        let startTime = Date.now
        var lastIPCount = 0
        var stableTime: Date?

        while true {
            let ipCount = lock.withLock { allIPs.count }

            // Track when IP count becomes stable
            if ipCount > 0 {
                if ipCount != lastIPCount {
                    lastIPCount = ipCount
                    stableTime = Date.now
                } else if let stable = stableTime, Date.now > stable.addingTimeInterval(0.5) {
                    // No new IPs for 500ms, we're done
                    break
                }
            }
            if permissionsDenied {
                throw SonosServiceError.permissionDenied
            }
            
            if Date.now > startTime.addingTimeInterval(8) {
                break
            }
            
            try? await Task.sleep(for: .milliseconds(50))
        }

        return lock.withLock { Array(allIPs) }
    }

    func startBrowseAll() {
        stopBrowsing()
        lock.withLock {
            allIPs.removeAll()
            // Cancel all existing connections before removing them to prevent leaks
            connections.forEach { $0?.cancel() }
            connections.removeAll()
            // Clean up stale cache entries (older than 5 minutes)
            let now = Date.now
            householdIDCache = householdIDCache.filter { now.timeIntervalSince($0.value.timestamp) < 300 }
        }

        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        params.allowFastOpen = true
        params.multipathServiceType = .handover // Enable multipath TCP for faster connection
        params.serviceClass = .responsiveData // Prioritize low latency

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
            guard case let .service(name, type, domain, interface) = service.endpoint else { continue }

            let netConnection = NWConnection(to: .service(name: name, type: type, domain: domain, interface: interface), using: .tcp)
            netConnection.stateUpdateHandler = { [weak self, weak netConnection] newState in
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
            netConnection.start(queue: .global())
            lock.withLock {
                connections.append(netConnection)
            }
        }
    }

    private func changeHandlerAll(_ services: Set<NWBrowser.Result>, _ changes: Set<NWBrowser.Result.Change>) {
        for service in services {
            guard case let .service(name, type, domain, interface) = service.endpoint else { continue }

            let netConnection = NWConnection(to: .service(name: name, type: type, domain: domain, interface: interface), using: .tcp)

            // State handler - extract IP when connection is ready (most reliable method)
            netConnection.stateUpdateHandler = { [weak self, weak netConnection] newState in
                guard let self else { return }

                switch newState {
                case .ready:
                    // Connection is ready - extract IP from currentPath
                    if let currentPath = netConnection?.currentPath,
                       let endpoint = currentPath.remoteEndpoint,
                       case let .hostPort(host, _) = endpoint,
                       let ip = host.debugDescription.components(separatedBy: "%").first {
                        self.lock.withLock {
                            self.allIPs.insert(ip)
                        }
                        self.logger.trace("Discovered Sonos IP: \(ip)")
                    }
                case .failed, .cancelled:
                    // Clean up failed connections
                    self.lock.withLock {
                        if let conn = netConnection, let index = self.connections.firstIndex(where: { $0 === conn }) {
                            self.connections.remove(at: index)
                        }
                    }
                default:
                    break
                }
            }

            netConnection.start(queue: .global())
            lock.withLock {
                connections.append(netConnection)
            }
        }
    }

    private func stateHandler(_ newState: NWBrowser.State) {
        lastKnownState = newState.debugDescription

        switch newState {
        case .ready:
            logger.trace("Browser ready. Starting browsing...")
        case let .failed(error):
            logger.trace("Browser failed with error: \(error)")
            // Don't auto-restart - let the caller handle retry logic
        case let .waiting(error):
            logger.trace("Browser waiting: \(error)")
            if let description = error.errorUserInfo["NSDescription"] as? String, description == "PolicyDenied" {
                logger.trace("Browser permission denied")
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
