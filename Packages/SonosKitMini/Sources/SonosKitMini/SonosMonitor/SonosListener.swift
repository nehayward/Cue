import Foundation
import Network
import os.log
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Configuration struct for SonosListener
struct SonosListenerConfig {
    let port: UInt16
    let queueLabel: String
    let backlogSize: Int32
    let bufferSize: Int
    let batchSize: Int  // Added for request batching
    let maxConcurrentConnections: Int  // Added for connection pooling
    
    init(
        port: UInt16,
        queueLabel: String =  "com.clic.sonos_server",
        backlogSize: Int32 = 256,  // Increased backlog size
        bufferSize: Int = 32768,   // Increased buffer size
        batchSize: Int = 10,
        maxConcurrentConnections: Int = 50
    ) {
        self.port = port
        self.queueLabel = queueLabel
        self.backlogSize = backlogSize
        self.bufferSize = bufferSize
        self.batchSize = batchSize
        self.maxConcurrentConnections = maxConcurrentConnections
    }
}

final class SonosListener {
    private let config: SonosListenerConfig
    private var socketHandle: Int32 = -1
    private let queue: DispatchQueue
    private var isRunning = false
    
    // Add delegate or callback for server ready state
    var onServerReady: (() -> Void)?
    var eventHandler: ((SonosServiceEvent, String) -> Void)?
    var zoneManagementHandler: ((SonosZoneEvent) -> Void)?
    
    private var sourceTimer: DispatchSourceTimer?
    
    private var activeConnections: Set<String> = []  // Track active Sonos device connections
    private let connectionQueue = DispatchQueue(label: "com.clic.connection_queue")
    
    // Update connection timeout to be longer
    private let connectionTimeout: TimeInterval = 300 // 5 minutes
    private let keepAliveInterval: TimeInterval = 60 // 1 minute
    private let maxReconnectAttempts = 3
    private var reconnectAttempts = 0
    
    private let standardResponseString = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
    private let standardResponse = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".data(using: .utf8)!
    
    private let bufferPool = BufferPool(size: 50, bufferSize: 32768)
    private var availableBuffers: [[UInt8]] = []
    private let maxBufferPoolSize = 10
    
    public var isActive: Bool {
        isRunning && socketHandle != -1
    }
    
    private var serverMonitorTimer: DispatchSourceTimer?
    private let serverCheckInterval: TimeInterval = 30 // Check every 30 seconds
    
    private let requestQueue = DispatchQueue(label: "com.clic.request_queue", attributes: .concurrent)
    private let rateLimiter = RateLimiter(requestsPerSecond: 100)
    private var pendingRequests: [(Data, String, String)] = []
    private let batchProcessingQueue = DispatchQueue(label: "com.clic.batch_processing")
    private var lastBatchProcessTime: TimeInterval = 0
    private let minimumBatchInterval: TimeInterval = 0.1 // 100ms
    
    private var clientSources: [Int32: DispatchSourceRead] = [:] {
        didSet {
            // Clean up when reaching high counts
            if clientSources.count > config.maxConcurrentConnections {
                let excessConnections = clientSources.count - config.maxConcurrentConnections
                let keysToRemove = Array(clientSources.keys.prefix(excessConnections))
                keysToRemove.forEach { socket in
                    clientSources[socket]?.cancel()
                    clientSources.removeValue(forKey: socket)
                }
            }
        }
    }
    
    private var clientBuffers: [Int32: Data] = [:] {
        didSet {
            // Clean up when reaching high counts
            if clientBuffers.count > config.maxConcurrentConnections {
                let excessConnections = clientBuffers.count - config.maxConcurrentConnections
                let keysToRemove = Array(clientBuffers.keys.prefix(excessConnections))
                keysToRemove.forEach { socket in
                    clientBuffers.removeValue(forKey: socket)
                }
            }
        }
    }
    
    private var expectedContentLengths: [Int32: Int] = [:] {
        didSet {
            // Clean up when reaching high counts
            if expectedContentLengths.count > config.maxConcurrentConnections {
                let excessConnections = expectedContentLengths.count - config.maxConcurrentConnections
                let keysToRemove = Array(expectedContentLengths.keys.prefix(excessConnections))
                keysToRemove.forEach { socket in
                    expectedContentLengths.removeValue(forKey: socket)
                }
            }
        }
    }
    
    private let sharedBuffer: UnsafeMutablePointer<UInt8>
    
    init(port: UInt16) {
        self.config = SonosListenerConfig(port: port)
        self.queue = DispatchQueue(label: config.queueLabel)
        // Allocate shared buffer
        self.sharedBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: config.bufferSize)
        #if !os(watchOS)
        setupLifecycleObservers()
        setupServer()
        startServerMonitoring()
        #endif
    }
    
    deinit {
        stopServerMonitoring()
        removeLifecycleObservers()
        stopServer()
        // Deallocate shared buffer
        sharedBuffer.deallocate()
    }
    
    private func setupLifecycleObservers() {
#if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
#elseif os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackground),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
#endif
    }
    
    private func removeLifecycleObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleBackground() {
        print("HTTPServer: App entering background")
        stopServer()
        // Clear all connections
        connectionQueue.sync {
            let count = activeConnections.count
            activeConnections.removeAll()
            print("Cleared \(count) active connections")
        }
    }
    
    @objc private func handleForeground() {
        print("HTTPServer: App entering foreground")
        // Clear old connections before starting
        connectionQueue.sync {
            activeConnections.removeAll()
        }
        // Start fresh server
        setupServer()
    }
    
    private func setupServer() {
        // First ensure we're not already running
        if isRunning {
            stopServer()
        }
        
        socketHandle = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketHandle != -1 else {
            os_log(.error, "Failed to create socket: %d", errno)
            return
        }
        
        configureSocketOptions()
        bindSocket()
        startListening()
    }
    
    private func configureSocketOptions() {
        // Set socket options before non-blocking mode
        var value: Int32 = 1
        let options = [
            (SOL_SOCKET, SO_REUSEADDR),
            (SOL_SOCKET, SO_REUSEPORT),
            (SOL_SOCKET, SO_NOSIGPIPE)
        ]
        
        for (level, option) in options {
            guard setsockopt(socketHandle, level, option, &value, socklen_t(MemoryLayout<Int32>.size)) != -1 else {
                os_log(.error, "Failed to set socket option %d: %d", option, errno)
                close(socketHandle)
                return
            }
        }
        
        // Set non-blocking mode after other options
        var flags = fcntl(socketHandle, F_GETFL)
        guard flags != -1 else {
            os_log(.error, "Failed to get socket flags: %d", errno)
            close(socketHandle)
            return
        }
        
        flags |= O_NONBLOCK
        guard fcntl(socketHandle, F_SETFL, flags) != -1 else {
            os_log(.error, "Failed to set non-blocking mode: %d", errno)
            close(socketHandle)
            return
        }
    }
    
    private func bindSocket() {
        // Create a new sockaddr_in with explicit initialization
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY
        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)
        
        // Try to bind with a retry mechanism and port incrementing
        var retryCount = 0
        let maxRetries = 7
        var bindResult: Int32 = -1
        var currentPort = config.port
        let maxPortIncrement = 10 // Maximum number of ports to try
        
        repeat {
            addr.sin_port = currentPort.bigEndian
            
            bindResult = withUnsafePointer(to: addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    bind(socketHandle, addr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            if bindResult == -1 {
                // Check for specific error conditions
                switch errno {
                case EADDRINUSE:
                    if UInt16(currentPort - config.port) < maxPortIncrement {
                        // Try next port
                        currentPort += 1
                        os_log(.info, "Port %d in use, trying port %d...", currentPort - 1, currentPort)
                        continue
                    }
                    fallthrough
                case EACCES:
                    if retryCount < maxRetries {
                        // Exponential backoff with longer initial delay
                        let waitTime = UInt32(pow(2.0, Double(retryCount))) * 500_000 // Start at 500ms
                        os_log(.info, "Bind failed (errno: %d), retrying in %d ms...", errno, waitTime/1000)
                        usleep(waitTime)
                        retryCount += 1
                        // Reset port to original when retrying
                        currentPort = config.port
                        continue
                    }
                default:
                    break
                }
                os_log(.error, "Failed to bind socket after %d retries: %d", retryCount, errno)
                close(socketHandle)
                return
            }
            break
        } while true
        
        os_log(.info, "Successfully bound socket to port %d after %d retries", currentPort, retryCount)
    }
    
    private func startListening() {
        var retryCount = 0
        let maxRetries = 5
        
        repeat {
            let result = listen(socketHandle, config.backlogSize)
            if result == -1 {
                // Check for specific error conditions
                switch errno {
                case EADDRINUSE, EACCES:
                    if retryCount < maxRetries {
                        // Exponential backoff with longer initial delay
                        let waitTime = UInt32(pow(2.0, Double(retryCount))) * 500_000 // Start at 500ms
                        os_log(.info, "Listen failed (errno: %d), retrying in %d ms...", errno, waitTime/1000)
                        usleep(waitTime)
                        retryCount += 1
                        continue
                    }
                default:
                    break
                }
                os_log(.error, "Failed to listen after %d retries: %d", retryCount, errno)
                close(socketHandle)
                return
            }
            break
        } while true
        
        os_log(.info, "Server successfully listening on port %d", config.port)
        isRunning = true
        setupAcceptTimer()
    }
    
    private func setupAcceptTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler(handler: { [weak self] in
            self?.checkForConnections()
        })
        timer.resume()
        sourceTimer = timer
        
        DispatchQueue.main.async { [weak self] in
            self?.onServerReady?()
        }
    }
    
    private func checkForConnections() {
        guard isRunning else { return }
        
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        while true {
            let clientSocket = withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    accept(socketHandle, addr, &len)
                }
            }
            
            if clientSocket == -1 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    // No more connections to accept right now
                    break
                }
                os_log(.error, "Accept failed with error: %d", errno)
                break
            }
            
            print("New connection accepted on socket: \(clientSocket)")
            queue.async { [weak self] in
                self?.handleClient(socket: clientSocket)
            }
        }
    }
    
    private func handleClient(socket: Int32) {
        // Set socket non-blocking
        var flags = fcntl(socket, F_GETFL)
        flags |= O_NONBLOCK
        guard fcntl(socket, F_SETFL, flags) != -1 else {
            os_log(.error, "Failed to set client socket non-blocking: %d", errno)
            close(socket)
            return
        }
        
        // Set keep-alive options
        var keepAlive: Int32 = 1
        var keepIdle: Int32 = 60 // Start probing after 60 seconds of inactivity
        var keepInterval: Int32 = 10 // Send probe every 10 seconds
        var keepCount: Int32 = 5 // Allow 5 probes before considering connection dead
        
        setsockopt(socket, SOL_SOCKET, SO_KEEPALIVE, &keepAlive, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socket, IPPROTO_TCP, TCP_KEEPALIVE, &keepIdle, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socket, IPPROTO_TCP, TCP_KEEPINTVL, &keepInterval, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socket, IPPROTO_TCP, TCP_KEEPCNT, &keepCount, socklen_t(MemoryLayout<Int32>.size))
        
        // Rest of handleClient implementation remains the same
        clientBuffers[socket] = Data()
        
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        
        source.setEventHandler { [weak self] in
            self?.handleRead(socket: socket)
        }
        
        source.setCancelHandler { [weak self] in
            print("Closing socket \(socket)")
            close(socket)
            self?.clientBuffers.removeValue(forKey: socket)
            self?.expectedContentLengths.removeValue(forKey: socket)
            self?.clientSources.removeValue(forKey: socket)
        }
        
        clientSources[socket] = source
        source.resume()
    }

    private var readSource: DispatchSourceRead?
    
    private func handleRead(socket: Int32) {
        repeat {
            let bytesRead = recv(socket, sharedBuffer, config.bufferSize, 0)
            
            if bytesRead > 0 {
                // Process data directly to avoid copying
                if clientBuffers[socket] == nil {
                    clientBuffers[socket] = Data()
                }
                clientBuffers[socket]?.append(sharedBuffer, count: bytesRead)
                
                // Try to process as many complete messages as possible
                while processBuffer(socket: socket) {}
                
            } else if bytesRead == 0 || (bytesRead == -1 && errno != EAGAIN) {
                clientSources[socket]?.cancel()
                return
            } else {
                break  // EAGAIN - no more data
            }
        } while true
    }
    
    private func processPendingRequests(socket: Int32) {
        let currentTime = Date().timeIntervalSince1970
        guard currentTime - lastBatchProcessTime >= minimumBatchInterval else { return }
        
        batchProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Process pending requests in batches
            while !self.pendingRequests.isEmpty {
                let batchSize = min(self.config.batchSize, self.pendingRequests.count)
                let batch = Array(self.pendingRequests.prefix(batchSize))
                self.pendingRequests.removeFirst(batchSize)
                
                for (data, completeStr, clientIP) in batch {
                    self.rateLimiter.execute { [weak self] in
                        self?.handleSonosResponse(data, completeStr, clientIP: clientIP)
                    }
                }
            }
            
            self.lastBatchProcessTime = currentTime
        }
    }
    
    private func processBuffer(socket: Int32) -> Bool {
        guard var data = clientBuffers[socket] else { return false }
        
        // Try to find complete message boundary
        if let contentLength = expectedContentLengths[socket] {
            guard data.count >= contentLength else { return false }
            
            let messageData = data.prefix(contentLength)
            data = data.dropFirst(contentLength)
            clientBuffers[socket] = data
            expectedContentLengths[socket] = nil
            processCompleteRequest(socket: socket, data: Data(messageData))
            return true
            
        } else if let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) {
            let headerEndIndex = headerEndRange.upperBound
            let headerData = data.prefix(headerEndIndex)
            
            if let length = parseContentLength(headerString: String(data: headerData, encoding: .utf8) ?? "") {
                expectedContentLengths[socket] = length
                if data.count >= headerEndIndex + length {
                    let messageData = data.prefix(headerEndIndex + length)
                    data = data.dropFirst(headerEndIndex + length)
                    clientBuffers[socket] = data
                    expectedContentLengths[socket] = nil
                    processCompleteRequest(socket: socket, data: Data(messageData))
                    return true
                }
            } else {
                let messageData = data.prefix(headerEndIndex)
                data = data.dropFirst(headerEndIndex)
                clientBuffers[socket] = data
                processCompleteRequest(socket: socket, data: Data(messageData))
                return true
            }
        }
        return false
    }

    private func parseContentLength(headerString: String) -> Int? {
        let lines = headerString.components(separatedBy: "\r\n")
        for line in lines {
            let lowercaseLine = line.lowercased()
            
            if lowercaseLine.hasPrefix("content-length:") {
                let value = lowercaseLine.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    
    private func processCompleteRequest(socket: Int32, data: Data) {
        let clientIP = getClientIP(socket: socket)
        
        // Process the request in background with rate limiting
        queue.async { [weak self] in
            // Add small delay between processing messages
            usleep(1000) // 1ms delay
            
            if let completeStr = String(data: data, encoding: .utf8) {
                self?.pendingRequests.append((data, completeStr, clientIP))
                self?.processPendingRequests(socket: socket)
            }
            
            // Send pre-computed response
            _ = self?.standardResponse.withUnsafeBytes { buffer in
                send(socket, buffer.baseAddress, buffer.count, 0)
            }
        }
    }
    
    private func getClientIP(socket: Int32) -> String {
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let peerResult = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                getpeername(socket, addr, &len)
            }
        }
        
        if peerResult == 0 {
            var ipString = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr.sin_addr, &ipString, socklen_t(INET_ADDRSTRLEN))
            return String(cString: ipString)
        }
        return "unknown"
    }
    
    private func handleSonosResponse(_ allData: Data, _ completeStr: String, clientIP: String) {
        // Parse headers to get SID and IP
        let headerInfo = parseHeaders(allData)
        
        if let xmlContent = completeStr.components(separatedBy: "\r\n\r\n").last,
           xmlContent.contains("<e:propertyset"),
           let deviceID = headerInfo.rinconID {
            
            // Track the new connection
            connectionQueue.sync {
                activeConnections.insert(deviceID)
                print("Active connections: \(activeConnections)")
            }
            
            // Parse and handle AVTransport events
            if let serviceType = headerInfo.serviceType {
                switch serviceType {
                case "AVTransport":
                    if let model = AVTransportParser.parse(xmlString: xmlContent) {
                        handleAVTransportEvent(model, deviceID, clientIP, headerInfo: headerInfo)
                    }
                case "GroupRenderingControl":
                    if let model = GroupRenderingControlParser.parse(xmlString: xmlContent) {
                        let event = SonosServiceEvent.groupRenderingControl(model)
                        eventHandler?(event, deviceID)
                    }
                case "RenderingControl":
                    if let model = RenderingControlParser.parse(xmlString: xmlContent) {
                        let event = SonosServiceEvent.renderingContrl(model)
                        eventHandler?(event, deviceID)
                        print("\nParsed RenderingControl Event:\n\(model)\n")
                    }
                case "DeviceProperties":
                    if let model = DevicePropertiesParser.parse(xmlString: xmlContent) {
                        let event = SonosServiceEvent.deviceProperties(model)
                        eventHandler?(event, deviceID)
                    }
                default:
                    print("Unknown service type: \(serviceType)")
                }
            }
        }
    }
    
    private func handleAVTransportEvent(_ model: SonosAVTransportEvent, _ deviceID: String, _ clientIP: String, headerInfo: HeaderInfo) {
        let event = SonosServiceEvent.avTransport(model)
        
        eventHandler?(event, deviceID)
        print("------- \(model.transportState?.lowercased()) ----------")
        
        if model.currentTrackURI.contains("rincon") {
            print("Yahoo!")
            let addGroupEvent = SonosZoneEvent.addGroup(model.groupedWithID!, headerInfo.rinconID!)
            zoneManagementHandler?(addGroupEvent)
        } else {
            let removeFromGroupsEvent = SonosZoneEvent.removeFromGroups(headerInfo.rinconID!)
            zoneManagementHandler?(removeFromGroupsEvent)
        }
        eventHandler?(event, deviceID)
        print("------- \(model.transportState?.lowercased()) ----------")
        
        Task {
            if let transportState = model.transportState?.lowercased(), transportState == "transitioning" {
                do {
                    // Poll until we reach a stable state
                    let isPlaying = try await SonosSoapAPI.pollTransportInfo(deviceIP: clientIP)
                    
                    // Get the final position
                    let position = try await SonosSoapAPI.getPositionInfo(deviceIP: clientIP)
                    let positionModel = SonosPosition(relativeTime: position.relativeTime)
                    let positionEvent = SonosServiceEvent.position(positionModel)
                    eventHandler?(positionEvent, deviceID)
                    
                    let updateTimeStamp = SonosServiceEvent.progress(.now)
                    eventHandler?(updateTimeStamp, deviceID)
                    eventHandler?(SonosServiceEvent.isPlaying(isPlaying), deviceID)
                } catch {
                    print("Error polling transport state: \(error)")
                }
            } else {
                // Original position info logic for non-transitioning states
                let position = try await SonosSoapAPI.getPositionInfo(deviceIP: clientIP)
                print(position)
                print("--------position--------")
                let positionModel = SonosPosition(relativeTime: position.relativeTime)
                let event = SonosServiceEvent.position(positionModel)
                let updateTimeStamp = SonosServiceEvent.progress(.now)
                eventHandler?(event, deviceID)
                eventHandler?(updateTimeStamp, deviceID)
                print(model.transportState)
                eventHandler?(SonosServiceEvent.isPlaying(model.transportState?.lowercased() == "playing"), deviceID)

            }
        }
    }
    
    private func parseHeaders(_ data: Data) -> HeaderInfo {
        guard let headerString = String(data: data, encoding: .utf8) else {
            return HeaderInfo(contentLength: nil, rinconID: nil, ipAddress: nil, serviceType: nil)
        }
        print("\n==== HTTP Headers ====\n")
        
        let lines = headerString.components(separatedBy: "\r\n")
        var contentLength: Int?
        var rinconID: String?
        var ipAddress: String?
        var serviceType: String?
        
        for line in lines {
            let lowercaseLine = line.lowercased()
            
            if lowercaseLine.hasPrefix("content-length:") {
                let value = lowercaseLine.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value)
            }
            
            if line.hasPrefix("SID:") {
                if let rinconRange = line.range(of: "RINCON_[A-Z0-9]*", options: .regularExpression) {
                    rinconID = String(line[rinconRange])
                    print("Sonos Device ID: \(rinconID!)")
                }
            }
            
            if line.hasPrefix("HOST:") {
                let hostValue = line.dropFirst("HOST:".count).trimmingCharacters(in: .whitespaces)
                print("Host: \(hostValue)")
                
                let components = hostValue.split(separator: ":")
                if let ip = components.first {
                    ipAddress = String(ip)
                    print("IP Address: \(ipAddress!)")
                }
            }
            
            if line.hasPrefix("X-SONOS-SERVICETYPE:") {
                serviceType = line.dropFirst("X-SONOS-SERVICETYPE:".count).trimmingCharacters(in: .whitespaces)
                print("X-SONOS-SERVICETYPE: \(serviceType ?? "none")")
            } else {
                print(line)
            }
        }
        print("\n====================\n")
        return HeaderInfo(
            contentLength: contentLength,
            rinconID: rinconID,
            ipAddress: ipAddress,
            serviceType: serviceType
        )
    }
    
    public func stopServer() {
        isRunning = false
        sourceTimer?.cancel()
        sourceTimer = nil
        
        // Cancel all client sources
        for source in clientSources.values {
            source.cancel()
        }
        clientSources.removeAll()
        clientBuffers.removeAll()
        expectedContentLengths.removeAll()
        
        if socketHandle != -1 {
            print("Shutting down server socket \(socketHandle)")
            shutdown(socketHandle, SHUT_RDWR)
            close(socketHandle)
            socketHandle = -1
        }
    }
    
    private func startServerMonitoring() {
        serverMonitorTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + serverCheckInterval, repeating: serverCheckInterval)
        timer.setEventHandler { [weak self] in
            self?.checkServerHealth()
        }
        timer.resume()
        serverMonitorTimer = timer
    }
    
    private func stopServerMonitoring() {
        serverMonitorTimer?.cancel()
        serverMonitorTimer = nil
    }
    
    private func checkServerHealth() {
        if !isActive {
            print("Server not listening, attempting restart...")
            restartServer()
        }
    }
    
    private func restartServer() {
        stopServer()
        // Don't clear connections during restart
        setupServer()
        print("Server restarted successfully")
    }
    
    public func start() async throws {
        if !isActive {
            let serverReady = AsyncStream<Void> { continuation in
                self.onServerReady = {
                    continuation.yield(())
                    continuation.finish()
                }
            }
            
            // Start the server
            restartServer()
            
            // Wait for server to be ready
            for await _ in serverReady {
                // Server is ready
                if !isActive {
                    throw NSError(domain: "SonosListener", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server failed to start"])
                }
                break
            }
        }
    }
    
    public func getActiveConnectionCount() -> Int {
        return connectionQueue.sync { activeConnections.count }
    }
    
    public func getActiveDevices() -> Set<String> {
        return connectionQueue.sync { activeConnections }
    }
    
    public func closeAllConnections() {
        connectionQueue.sync {
            let count = activeConnections.count
            activeConnections.removeAll()
            print("Manually cleared \(count) active connections")
        }
    }
    
    public func closeConnection(deviceID: String) {
        connectionQueue.sync {
            activeConnections.remove(deviceID)
            print("Manually closed connection for device: \(deviceID)")
        }
    }
}

final class BufferPool {
    private var availableBuffers: [(id: Int, buffer: [UInt8])] = []
    private let semaphore: DispatchSemaphore
    private let queue = DispatchQueue(label: "com.clic.buffer_pool")
    
    init(size: Int, bufferSize: Int) {
        semaphore = DispatchSemaphore(value: size)
        for i in 0..<size {
            availableBuffers.append((i, [UInt8](repeating: 0, count: bufferSize)))
        }
    }
    
    func acquire() -> (id: Int, buffer: [UInt8])? {
        guard semaphore.wait(timeout: .now() + .seconds(5)) == .success else {
            return nil
        }
        
        return queue.sync {
            return availableBuffers.removeFirst()
        }
    }
    
    func release(_ buffer: (id: Int, buffer: [UInt8])) {
        queue.sync {
            availableBuffers.append(buffer)
        }
        semaphore.signal()
    }
}

final class RateLimiter {
    private let queue = DispatchQueue(label: "com.clic.rate_limiter")
    private let requestsPerSecond: Int
    private var lastExecutionTime: TimeInterval = 0
    
    init(requestsPerSecond: Int) {
        self.requestsPerSecond = requestsPerSecond
    }
    
    func execute(_ block: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let currentTime = Date().timeIntervalSince1970
            let timeSinceLastExecution = currentTime - self.lastExecutionTime
            let minimumInterval = 1.0 / Double(self.requestsPerSecond)
            
            if timeSinceLastExecution < minimumInterval {
                Thread.sleep(forTimeInterval: minimumInterval - timeSinceLastExecution)
            }
            
            self.lastExecutionTime = currentTime
            block()
        }
    }
}
