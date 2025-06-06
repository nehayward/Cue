import Foundation

/// A class for communicating with Sonos devices using WebSocket
public final class SonosWebSocket: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate {
    // MARK: - Properties
    
    /// The API key used for authentication
    private let apiKey: String
    
    /// Maximum number of retry attempts for failed operations
    private let maxAttempts: Int = 3
    
    /// Timeout interval for operations in seconds
    private var timeout: TimeInterval = 6
    
    /// Access token for authentication
    private let accessToken: String
    
    /// Whether debug logging is enabled
    private let debug: Bool
    
    /// The WebSocket task for communication
    private var webSocketTask: URLSessionWebSocketTask?
    
    /// The URL session for managing WebSocket connections
    private var session: URLSession!
    
    /// The current group ID
    private var groupId: String?
    
    /// The current household ID
    private var householdId: String?
    
    /// The current player ID
    private var playerId: String?
    
    /// Whether the WebSocket is currently connected
    private var isConnected = false
    
    /// Continuation for handling command responses
    private var responseContinuation: CheckedContinuation<Data, Error>?
    
    /// Continuation for handling metadata updates
    private var metadataStream: AsyncStream<MetadataStatusUpdate>.Continuation?
    
    // MARK: - Initialization
    
    /// Creates a new SonosWebSocket instance
    /// - Parameters:
    ///   - apiKey: The Sonos API key (defaults to a test key)
    ///   - debug: Whether to enable debug logging (defaults to false)
    public init(apiKey: String = "123e4567-e89b-12d3-a456-426655440000", debug: Bool = false) {
        self.accessToken = apiKey
        self.apiKey = apiKey
        self.debug = debug
        super.init()
        
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }
    
    /// Creates a new SonosWebSocket instance with a custom timeout
    /// - Parameters:
    ///   - apiKey: The Sonos API key
    ///   - timeout: Custom timeout interval in seconds
    ///   - debug: Whether to enable debug logging
    public convenience init(apiKey: String, timeout: TimeInterval, debug: Bool = false) {
        self.init(apiKey: apiKey, debug: debug)
        self.timeout = timeout
    }
    
    // MARK: - Public Methods
    
    /// Connects to a Sonos device
    /// - Parameters:
    ///   - ipAddress: The IP address of the Sonos device
    ///   - playerId: Optional player ID if known
    ///   - householdId: Optional household ID if known
    /// - Throws: `SonosWebSocketError` if connection fails
    public func connect(ipAddress: String, playerId: String? = nil, householdId: String? = nil) async throws {
        debugPrint("DEBUG: Opening websocket to wss://\(ipAddress):1443/websocket/api")
        self.playerId = playerId
        self.householdId = householdId
        
        guard let url = URL(string: "wss://\(ipAddress):1443/websocket/api") else {
            throw SonosWebSocketError.websocketError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(apiKey, forHTTPHeaderField: "X-Sonos-Api-Key")
        request.setValue("v1.api.smartspeaker.audio", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
        
        try await withTimeout(seconds: timeout) {
            while !self.isConnected {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
    
    /// Closes the WebSocket connection
    public func close() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
    }

    /// Gets information about the currently playing song using an IP address and group ID
    /// - Parameters:
    ///   - ipAddress: The IP address of the Sonos device
    ///   - groupID: The group ID to get song info for
    /// - Returns: A `SongInfo` object containing details about the current song
    /// - Throws: `SonosWebSocketError` if the operation fails
    public func getSongInfo(ipAddress: String, groupID: String) async throws -> SongInfo {
        // First connect to the device
        try await connect(ipAddress: ipAddress)
        
        // Get the household ID
        let householdId = try await getHouseholdId()
        
        // Now get the song info using the group ID
        return try await getSongInfo(groupID: groupID)
    }
    
    /// Gets information about the currently playing song
    /// - Parameter groupID: The group ID to get song info for
    /// - Returns: A `SongInfo` object containing details about the current song
    /// - Throws: `SonosWebSocketError` if the operation fails
    public func getSongInfo(groupID: String) async throws -> SongInfo {
        let householdId = try await getHouseholdId()
        
        let metadataCommand: [String: Any] = [
            "namespace": "playbackMetaData:1",
            "command": "getMetadataStatus",
            "householdId": householdId,
            "groupId": groupID
        ]
        
        let response: MetadataResponse = try await sendCommand(metadataCommand)
        
        guard let currentItem = response.currentItem,
              let track = currentItem.track else {
            throw SonosWebSocketError.websocketError("Could not get current item metadata")
        }
        
        return SongInfo(
            title: track.name,
            artist: track.artist.name,
            album: track.album.name,
            albumArtUri: track.imageUrl,
            duration: track.durationMillis / 1000, // Convert to seconds
            currentTime: nil, // Not available in this response
            queuePosition: nil, // Not available in this response
            queueLength: nil, // Not available in this response
            playbackState: nil, // Not available in this response
            quality: AudioQuality(
                bitDepth: track.quality.bitDepth,
                sampleRate: track.quality.sampleRate,
                lossless: track.quality.lossless,
                immersive: track.quality.immersive,
                _objectType: track.quality._objectType
            )
        )
    }
    
    /// Plays an audio clip on the Sonos device
    /// - Parameters:
    ///   - uri: The URI of the audio clip to play
    ///   - volume: Optional volume level (0-100)
    /// - Returns: The response from the Sonos device
    /// - Throws: `SonosWebSocketError` if the operation fails
    public func playClip(uri: String, volume: Int? = nil) async throws -> AudioClipResponse {
        let command: [String: Any] = [
            "namespace": "audioClip:1",
            "command": "loadAudioClip",
            "playerId": try await getPlayerId()
        ]
        
        var options: [String: Any] = [
            "name": "Sonos Websocket",
            "appId": "com.jjlawren.sonos_websocket",
            "streamUrl": uri
        ]
        
        if let volume = volume {
            options["volume"] = volume
        }
        
        return try await sendCommand(command, options: options)
    }
    
    /// Subscribes to playback metadata updates for a specific group
    /// - Parameter groupId: The group ID to subscribe to
    /// - Returns: An AsyncStream of metadata updates
    /// - Throws: `SonosWebSocketError` if the operation fails
    public func subscribeToPlaybackMetadata(groupId: String) async throws -> AsyncStream<MetadataStatusUpdate> {
        let (stream, continuation) = AsyncStream<MetadataStatusUpdate>.makeStream()
        self.metadataStream = continuation
        
        let householdId = try await getHouseholdId()
        let subscribeCommand: [String: Any] = [
            "namespace": "playbackMetadata:1",
            "command": "subscribe",
            "householdId": householdId,
            "groupId": groupId
        ]
        
        let response: SubscriptionResponse = try await sendCommand(subscribeCommand)
        guard response.success else {
            continuation.finish()
            throw SonosWebSocketError.websocketError("Failed to subscribe to playback metadata")
        }
        
        return stream
    }
    
    /// Subscribes to group updates
    /// - Parameter groupId: The group ID to subscribe to
    /// - Returns: An AsyncStream of metadata updates
    /// - Throws: `SonosWebSocketError` if the operation fails
    public func subscribeToGroups(groupId: String) async throws -> AsyncStream<MetadataStatusUpdate> {
        let (stream, continuation) = AsyncStream<MetadataStatusUpdate>.makeStream()
        self.metadataStream = continuation
        
        let householdId = try await getHouseholdId()
        let subscribeCommand: [String: Any] = [
            "namespace": "groups:1",
            "command": "subscribe",
            "householdId": householdId
        ]
        
        let response: SubscriptionResponse = try await sendCommand(subscribeCommand)
        guard response.success else {
            continuation.finish()
            throw SonosWebSocketError.websocketError("Failed to subscribe to group updates")
        }
        
        return stream
    }
    
    /// Connects to a Sonos device and subscribes to playback metadata updates
    /// - Parameters:
    ///   - ipAddress: The IP address of the Sonos device
    ///   - groupId: The group ID to subscribe to
    /// - Returns: An AsyncStream of metadata updates
    /// - Throws: `SonosWebSocketError` if the operation fails
    public func connectAndSubscribe(ipAddress: String, groupId: String) async throws -> AsyncStream<MetadataStatusUpdate> {
        try await connect(ipAddress: ipAddress)
        return try await subscribeToPlaybackMetadata(groupId: groupId)
    }
    
    /// Gets information about all groups in the household
    /// - Returns: A `GroupResponse` containing information about all groups
    /// - Throws: `SonosWebSocketError` if the operation fails
    public func getGroups() async throws -> GroupResponse {
        let householdId = try await getHouseholdId()
        let groupsCommand: [String: Any] = [
            "namespace": "groups:1",
            "command": "getGroups",
            "householdId": householdId
        ]
        
        return try await sendCommand(groupsCommand)
    }
    
    // MARK: - Private Methods
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SonosWebSocketError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func debugPrint(_ items: Any...) {
        if debug {
            print(items)
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.debugPrint(text)
                    if let data = text.data(using: .utf8) {
                        // Handle subscription updates
                        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                           jsonArray.count >= 2 {
                            // First check if this is a metadata status update
                            if let firstItem = jsonArray[0] as? [String: Any],
                               let name = firstItem["name"] as? String,
                               name == "playbackMetadataStatus",
                               let secondItem = jsonArray[1] as? [String: Any] {
                                
                                // Create a new dictionary with the metadata status fields
                                var metadataStatus: [String: Any] = [:]
                                
                                // Add fields from first item
                                metadataStatus["namespace"] = firstItem["namespace"]
                                metadataStatus["householdId"] = firstItem["householdId"]
                                metadataStatus["locationId"] = firstItem["locationId"]
                                metadataStatus["groupId"] = firstItem["groupId"]
                                metadataStatus["name"] = name
                                metadataStatus["type"] = firstItem["type"]
                                
                                // Add fields from second item
                                metadataStatus["_objectType"] = secondItem["_objectType"]
                                metadataStatus["container"] = secondItem["container"]
                                metadataStatus["currentItem"] = secondItem["currentItem"]
                                metadataStatus["nextItem"] = secondItem["nextItem"]
                                
                                self.debugPrint("Processing metadata update: \(metadataStatus)")
                                
                                if let updateData = try? JSONSerialization.data(withJSONObject: metadataStatus),
                                   let update = try? JSONDecoder().decode(MetadataStatusUpdate.self, from: updateData) {
                                    self.debugPrint("Yielding metadata update: \(update)")
                                    self.metadataStream?.yield(update)
                                } else {
                                    self.debugPrint("Failed to decode metadata update")
                                }
                            }
                        }
                        
                        // Handle command responses
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                           let continuation = self.responseContinuation {
                            self.responseContinuation = nil
                            continuation.resume(returning: data)
                        }
                    }
                case .data(let data):
                    self.debugPrint("DEBUG: Received data: \(data)")
                @unknown default:
                    break
                }
                self.receiveMessage()
                
            case .failure(let error):
                if let continuation = self.responseContinuation {
                    self.responseContinuation = nil
                    continuation.resume(throwing: SonosWebSocketError.connectionError(error.localizedDescription))
                }
                self.metadataStream?.finish()
            }
        }
    }
    
    private func sendCommand<T: Codable>(_ command: [String: Any], options: [String: Any]? = nil) async throws -> T {
        var attempt = 1
        while attempt <= maxAttempts {
            do {
                if !isConnected {
                    try await connect(ipAddress: "", playerId: playerId, householdId: householdId)
                }
                
                let payload: [Any] = [command, options ?? [:]]
                debugPrint("DEBUG: Sending command: \(payload)")
                
                let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    self.responseContinuation = continuation
                    
                    if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
                        let message = URLSessionWebSocketTask.Message.data(data)
                        
                        webSocketTask?.send(message) { error in
                            if let error = error {
                                continuation.resume(throwing: SonosWebSocketError.websocketError(error.localizedDescription))
                            }
                        }
                        
                        Task {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                                if let continuation = self.responseContinuation {
                                    self.responseContinuation = nil
                                    continuation.resume(throwing: SonosWebSocketError.timeout)
                                }
                            } catch {}
                        }
                    } else {
                        continuation.resume(throwing: SonosWebSocketError.websocketError("Failed to serialize command"))
                    }
                }
                
                debugPrint("DEBUG: Received raw response: \(String(decoding: responseData, as: UTF8.self))")
                
                // Parse the response data into the expected type
                if let jsonArray = try? JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] {
                    debugPrint("DEBUG: Parsed JSON array: \(jsonArray)")
                    
                    // For empty commands (like getting household ID), use the first item
                    if command.isEmpty {
                        if let firstItem = jsonArray.first,
                           let data = try? JSONSerialization.data(withJSONObject: firstItem) {
                            return try JSONDecoder().decode(T.self, from: data)
                        }
                    }
                    // For subscription responses, use the first item
                    else if command["command"] as? String == "subscribe" {
                        if let firstItem = jsonArray.first,
                           let data = try? JSONSerialization.data(withJSONObject: firstItem) {
                            let response = try JSONDecoder().decode(SubscriptionResponse.self, from: data)
                            return response as! T
                        }
                    }
                    // For other commands, use the second item
                    else if jsonArray.count >= 2,
                            let metadataItem = jsonArray[1] as? [String: Any],
                            let data = try? JSONSerialization.data(withJSONObject: metadataItem) {
                        return try JSONDecoder().decode(T.self, from: data)
                    }
                }
                
                throw SonosWebSocketError.websocketError("Failed to parse response")
                
            } catch {
                debugPrint("DEBUG: Attempt \(attempt) failed with error: \(error)")
                attempt += 1
                if attempt > maxAttempts {
                    throw SonosWebSocketError.websocketError("Command failed after \(maxAttempts) attempts")
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        
        throw SonosWebSocketError.websocketError("Command failed after \(maxAttempts) attempts")
    }
    
    private func getHouseholdId() async throws -> String {
        if let householdId = householdId {
            return householdId
        }
        
        let response: HouseholdResponse = try await sendCommand([:])
        self.householdId = response.householdId
        return response.householdId
    }
    
    private func getPlayerId() async throws -> String {
        if let playerId = playerId {
            return playerId
        }
        
        let response: GroupResponse = try await getGroups()
        guard let players = response.groups.first?.players else {
            throw SonosWebSocketError.websocketError("No players found in group data")
        }
        
        for player in players {
            if !player.capabilities.contains("AUDIO_CLIP") {
                continue
            }
            self.playerId = player.id
            return player.id
        }
        
        throw SonosWebSocketError.websocketError("No matching player found in group data")
    }
    
    // MARK: - URLSessionDelegate
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        if let continuation = responseContinuation {
            responseContinuation = nil
            continuation.resume(throwing: SonosWebSocketError.connectionError("WebSocket disconnected"))
        }
        metadataStream?.finish()
    }
} 
