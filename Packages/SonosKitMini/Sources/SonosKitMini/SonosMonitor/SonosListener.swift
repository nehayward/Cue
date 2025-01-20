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
    
    init(
        port: UInt16,
        queueLabel: String =  "com.clic.sonos_server",
        backlogSize: Int32 = 128,
        bufferSize: Int = 16384
    ) {
        self.port = port
        self.queueLabel = queueLabel
        self.backlogSize = backlogSize
        self.bufferSize = bufferSize
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
    
    // Add connection timeout and reconnect settings
    private let connectionTimeout: TimeInterval = 30
    private let maxReconnectAttempts = 3
    private var reconnectAttempts = 0
    
    private let standardResponseString = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
    private let standardResponse = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".data(using: .utf8)!
    
    private let bufferPool = DispatchQueue(label: "com.clic.buffer_pool")
    private var availableBuffers: [[UInt8]] = []
    private let maxBufferPoolSize = 10
    
    init(port: UInt16) {
        self.config = SonosListenerConfig(port: port)
        self.queue = DispatchQueue(label: config.queueLabel)
        setupLifecycleObservers()
        setupServer()
    }
    
    deinit {
        removeLifecycleObservers()
        stopServer()
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
        
        // Initialize buffer for this client
        clientBuffers[socket] = Data()
        
        // Create read source for client socket
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
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var clientBuffers: [Int32: Data] = [:]
    private var expectedContentLengths: [Int32: Int] = [:]
    
    private func getBuffer() -> [UInt8] {
        return bufferPool.sync {
            if let buffer = availableBuffers.popLast() {
                return buffer
            }
            return [UInt8](repeating: 0, count: config.bufferSize)
        }
    }
    
    private func recycleBuffer(_ buffer: [UInt8]) {
        bufferPool.async {
            if self.availableBuffers.count < self.maxBufferPoolSize {
                self.availableBuffers.append(buffer)
            }
        }
    }
    
    private func handleRead(socket: Int32) {
        var buffer = getBuffer()
        defer { recycleBuffer(buffer) }
        
        repeat {
            let bytesRead = recv(socket, &buffer, buffer.count, 0)
            
            if bytesRead > 0 {
                clientBuffers[socket]?.append(contentsOf: buffer[..<bytesRead])
                
                if processBuffer(socket: socket) {
                    break  // Request fully processed
                }
            } else if bytesRead == 0 || (bytesRead == -1 && errno != EAGAIN) {
                clientSources[socket]?.cancel()
                return
            } else {
                break  // EAGAIN - no more data
            }
        } while true
    }
    
    private func processBuffer(socket: Int32) -> Bool {
        guard let data = clientBuffers[socket] else { return false }
        
        if let contentLength = expectedContentLengths[socket] {
            if data.count >= contentLength {
                processCompleteRequest(socket: socket)
                return true
            }
        } else if let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) {
            let headerEndIndex = headerEndRange.upperBound
            
            if let length = parseContentLength(from: data[..<headerEndIndex]) {
                expectedContentLengths[socket] = length
                if data.count >= headerEndIndex + length {
                    processCompleteRequest(socket: socket)
                    return true
                }
            } else {
                processCompleteRequest(socket: socket)
                return true
            }
        }
        return false
    }
    
    private func parseContentLength(from data: Data) -> Int? {
        // Look for the header in binary data
        let contentLengthPattern = "Content-Length: ".data(using: .utf8)!
        if let range = data.range(of: contentLengthPattern) {
            let startIndex = range.upperBound
            // Find end of line
            if let endRange = data[startIndex...].firstIndex(of: UInt8(ascii: "\r")) {
                // Extract and parse the length value
                let lengthData = data[startIndex..<endRange]
                if let lengthStr = String(data: lengthData, encoding: .utf8),
                   let length = Int(lengthStr.trimmingCharacters(in: .whitespaces)) {
                    return length
                }
            }
        }
        return nil
    }
    
    private func processCompleteRequest(socket: Int32) {
        guard let data = clientBuffers[socket] else {
            clientSources[socket]?.cancel()
            return
        }
        
        let clientIP = getClientIP(socket: socket)
        
        // Process the request in background
        queue.async { [weak self] in
            if let completeStr = String(data: data, encoding: .utf8) {
                self?.handleSonosResponse(data, completeStr, clientIP: clientIP)
            }
            
            // Send pre-computed response
            _ = self?.standardResponse.withUnsafeBytes { buffer in
                send(socket, buffer.baseAddress, buffer.count, 0)
            }
            
            // Clear resources
            self?.clientSources[socket]?.cancel()
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
                    print("TODO")
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
    
    private func stopServer() {
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
    
    func getActiveConnectionCount() -> Int {
        return connectionQueue.sync { activeConnections.count }
    }
    
    func getActiveDevices() -> Set<String> {
        return connectionQueue.sync { activeConnections }
    }
}


