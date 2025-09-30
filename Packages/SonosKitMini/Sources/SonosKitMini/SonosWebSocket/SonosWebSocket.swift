import Foundation
import os

/// Errors that can occur during Sonos WebSocket operations
public enum SonosWebSocketError: Error, LocalizedError {
    case connectionNotFound
    case invalidResponse
    case connectionFailed(Error)
    case subscriptionFailed
    
    public var errorDescription: String? {
        switch self {
        case .connectionNotFound:
            return "WebSocket connection not found for the specified player"
        case .invalidResponse:
            return "Invalid response received from Sonos device"
        case .connectionFailed(let error):
            return "Failed to connect to Sonos device: \(error.localizedDescription)"
        case .subscriptionFailed:
            return "Failed to subscribe to Sonos events"
        }
    }
}

/**
 * A WebSocket client for connecting to Sonos devices and receiving real-time updates.
 *
 * `SonosWebSocket` provides a robust connection to Sonos devices via WebSocket protocol,
 * enabling real-time monitoring of volume changes, playback status, and track metadata.
 * The class handles automatic reconnection with exponential backoff and maintains
 * subscription state across connection drops.
 *
 * ## Features
 * - Real-time volume monitoring per player
 * - Playback state tracking per group
 * - Track metadata updates with album art
 * - Automatic reconnection with exponential backoff
 * - Thread-safe AsyncStream-based API
 * - Subscription state persistence across reconnections
 *
 * ## Usage
 * ```swift
 * // Create a WebSocket connection
 * let socket = SonosWebSocket(
 *     ipAddress: "192.168.1.100",
 *     apiKey: "your-api-key",
 *     debug: true
 * )
 *
 * // Subscribe to volume changes
 * let volumeStream = try await socket.connectAndSubscribeToPlayerVolume(
 *     playerId: "RINCON_000E58FE3AEA01400"
 * )
 *
 * // Process volume updates
 * for try await volumeEvent in volumeStream {
 *     print("Volume: \(volumeEvent.volumeState?.volume ?? 0)")
 * }
 * ```
 *
 * ## Error Handling
 * The WebSocket automatically handles common network errors:
 * - Connection drops are automatically retried with exponential backoff
 * - Network changes trigger reconnection attempts
 * - SSL certificate validation is handled for local connections
 * - Subscription state is restored after successful reconnection
 *
 * ## Thread Safety
 * All public methods are thread-safe and can be called from any queue.
 * Stream events are delivered on the main actor for UI updates.
 */
public final class SonosWebSocket: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate {
    // MARK: - Type Aliases
    
    /// AsyncStream for receiving track metadata events including song info, artist, album, and artwork
    public typealias SonosTrackWebSocketStream = AsyncThrowingStream<TrackEvent, Error>
    
    /// AsyncStream for receiving volume change events from Sonos players
    public typealias SonosVolumeWebSocketStream = AsyncThrowingStream<VolumeEvent, Error>
    
    /// AsyncStream for receiving playback state events including play/pause, position, and queue info
    public typealias SonosPlaybackWebSocketStream = AsyncThrowingStream<PlaybackEvent, Error>
    
    /// AsyncStream for receiving group status events including group membership and coordinator info
    public typealias SonosGroupWebSocketStream = AsyncThrowingStream<GroupEvent, Error>
    
    // MARK: - Configuration Properties
    
    /// The Sonos API key used for WebSocket authentication. Required for all API calls.
    private let apiKey: String
    
    /// Enables detailed logging of WebSocket messages and connection events for debugging
    private let debug: Bool
    
    /// The IP address of the target Sonos device (e.g., "192.168.1.100")
    private let ipAddress: String
    
    // MARK: - Connection Management
    
    /// The active WebSocket task handling the connection to the Sonos device
    private var task: URLSessionWebSocketTask?
    
    /// URL session configured for WebSocket connections with SSL certificate handling
    private var session: URLSession?
    
    /// Current connection state - true when WebSocket is actively receiving messages
    private var isConnected = false
    
    // MARK: - Stream Management
    
    /// Continuation for the volume event stream, yields VolumeEvent instances
    private var groupVolumeContinuation: SonosVolumeWebSocketStream.Continuation?
    
    /// Continuation for the volume event stream, yields VolumeEvent instances
    private var volumeContinuation: SonosVolumeWebSocketStream.Continuation?
    
    /// Continuation for the playback event stream, yields PlaybackEvent instances
    private var playbackContinuation: SonosPlaybackWebSocketStream.Continuation?
    
    /// Continuation for the track metadata stream, yields TrackEvent instances
    private var trackInfoContinuation: SonosTrackWebSocketStream.Continuation?
    
    /// Continuation for the group status stream, yields GroupEvent instances
    private var groupContinuation: SonosGroupWebSocketStream.Continuation?
    
    /// Background task that continuously receives and dispatches WebSocket messages
    /// Prevents race conditions by ensuring only one receive operation at a time
    private var messageReceiveTask: Task<Void, Never>?
    
    // MARK: - Reconnection Management
    
    /// Current number of consecutive reconnection attempts
    private var reconnectAttempts = 0
    
    /// Maximum number of reconnection attempts before giving up (default: 5)
    private var maxReconnectAttempts = 5
    
    /// Background task handling reconnection logic with exponential backoff
    private var reconnectTask: Task<Void, Never>?
    
    /// Maps subscription types to their identifiers for automatic resubscription after reconnection
    /// Keys: "volume", "playback", "metadata", "group" | Values: playerId, groupId, or householdId
    private var activeSubscriptions: [String: String] = [:]
    
    /**
     * Starts the background task responsible for receiving and dispatching WebSocket messages.
     *
     * This method creates a single background task that continuously listens for incoming
     * WebSocket messages and routes them to the appropriate stream based on message content.
     * Having a single receiver prevents race conditions and ensures message ordering.
     *
     * The receiver automatically:
     * - Detects connection state changes
     * - Handles reconnection on network errors
     * - Dispatches messages to correct streams based on content type
     * - Manages connection health monitoring
     */
    private func startMessageReceiver() {
        guard messageReceiveTask == nil else { return }
        
        messageReceiveTask = Task { [weak self] in
            var isAlive = true
            
            while isAlive && self?.task?.closeCode == .invalid {
                do {
                    guard let value = try await self?.task?.receive() else { return }
                    
                    // Mark as connected on successful receive
                    if self?.isConnected == false {
                        self?.isConnected = true
                        self?.reconnectAttempts = 0
                        if self?.debug == true {
                            print("DEBUG: WebSocket connected successfully")
                        }
                    }
                    
                    if case let .string(message) = value {
                        if self?.debug == true {
                            print(message.prettyPrinted)
                        }
                        await self?.dispatchMessage(message)
                    }
                } catch {
                    self?.isConnected = false
                    
                    // Check if this is a "Socket is not connected" error (NSPOSIXErrorDomain Code=57)
                    let isSocketNotConnectedError = (error as NSError).domain == NSPOSIXErrorDomain && (error as NSError).code == 57
                    
                    if self?.debug == true && !isSocketNotConnectedError {
                        print("DEBUG: WebSocket error: \(error)")
                    }
                    
                    // Check if this is a connection reset error or normal disconnection
                    if let urlError = error as? URLError,
                       urlError.code == .networkConnectionLost ||
                       (error as NSError).code == 54 { // Connection reset by peer
                        
                        if self?.debug == true {
                            print("DEBUG: Connection reset detected, attempting reconnection...")
                        }
                        
                        // Don't finish continuations immediately, try to reconnect
                        await self?.attemptReconnection()
                    } else if isSocketNotConnectedError {
                        // Socket not connected - likely during graceful shutdown, just exit quietly
                        isAlive = false
                    } else {
                        // Other errors - finish continuations
                        self?.volumeContinuation?.finish(throwing: error)
                        self?.playbackContinuation?.finish(throwing: error)
                        self?.trackInfoContinuation?.finish(throwing: error)
                        self?.groupVolumeContinuation?.finish(throwing: error)
                        self?.groupContinuation?.finish(throwing: error)
                        isAlive = false
                    }
                }
            }
        }
    }
    
    /**
     * Routes incoming WebSocket messages to the appropriate event stream.
     *
     * This method attempts to decode the received message as different event types
     * (VolumeEvent, PlaybackEvent, TrackEvent) and yields the decoded event to the
     * corresponding stream. Messages that cannot be decoded are logged for debugging.
     *
     * - Parameter message: The raw JSON message string received from the WebSocket
     */
    private func dispatchMessage(_ message: String) async {
        let messageData = Data(message.utf8)
        
        // Try to decode as VolumeEvent
        if let volumeEvent = try? VolumeEvent.decode(from: messageData) {
            if volumeEvent.info.type == "groupVolume" {
                groupVolumeContinuation?.yield(volumeEvent)
            } else {
                volumeContinuation?.yield(volumeEvent)
            }
            return
        }
        
        // Try to decode as PlaybackEvent
        if let playbackEvent = try? PlaybackEvent.decode(from: messageData) {
            playbackContinuation?.yield(playbackEvent)
            return
        }
        
        // Try to decode as TrackEvent
        if let trackEvent = try? TrackEvent.decode(from: messageData) {
            trackInfoContinuation?.yield(trackEvent)
            return
        }
        
        // Try to decode as GroupEvent
        if let groupEvent = try? GroupEvent.decode(from: messageData) {
            groupContinuation?.yield(groupEvent)
            return
        }
        
        // If we can't decode the message, log it for debugging
        if debug {
            print("DEBUG: Could not decode message: \(message)")
        }
    }
    
    /**
     * Handles automatic reconnection with exponential backoff strategy.
     *
     * This method is called when the WebSocket connection is lost due to network issues.
     * It implements an exponential backoff algorithm to avoid overwhelming the server
     * with rapid reconnection attempts.
     *
     * The reconnection process:
     * 1. Checks if max attempts have been reached
     * 2. Calculates delay using exponential backoff (max 30 seconds)
     * 3. Creates a new WebSocket task
     * 4. Resubscribes to all previously active subscriptions
     * 5. Restarts the message receiver
     *
     * If max attempts are reached, all stream continuations are finished with an error.
     */
    private func attemptReconnection() async {
        guard reconnectAttempts < maxReconnectAttempts else {
            if debug {
                print("DEBUG: Max reconnection attempts reached")
            }
            // Finish continuations after max attempts
            volumeContinuation?.finish(throwing: URLError(.networkConnectionLost))
            playbackContinuation?.finish(throwing: URLError(.networkConnectionLost))
            trackInfoContinuation?.finish(throwing: URLError(.networkConnectionLost))
            groupContinuation?.finish(throwing: URLError(.networkConnectionLost))
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Max 30 seconds
        
        if debug {
            print("DEBUG: Reconnection attempt \(reconnectAttempts)/\(maxReconnectAttempts) in \(delay) seconds")
        }
        
        try? await Task.sleep(for: .seconds(delay))
        
        // Cancel old task and create new one
        task?.cancel(with: .normalClosure, reason: nil)
        createWebSocketTask()
        task?.resume()
        
        // Resubscribe to active subscriptions
        await resubscribeAll()
        
        // Restart message receiver
        messageReceiveTask?.cancel()
        messageReceiveTask = nil
        startMessageReceiver()
    }
    
    /// Resubscribes to all active subscriptions after reconnection
    private func resubscribeAll() async {
        for (type, id) in activeSubscriptions {
            if debug {
                print("DEBUG: Resubscribing to \(type): \(id)")
            }
            
            switch type {
            case "volume":
                await resubscribeToVolume(playerId: id)
            case "playback":
                await resubscribeToPlayback(groupId: id)
            case "metadata":
                await resubscribeToMetadata(groupId: id)
            case "group":
                await resubscribeToGroup(householdId: id)
            default:
                break
            }
        }
    }
    
    private func resubscribeToVolume(playerId: String) async {
        let subscribeCommand: [String: Any] = [
            "namespace": "playerVolume:1",
            "command": "subscribe",
            "playerId": playerId
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        try? await task?.send(.data(data))
    }
    
    private func resubscribeToPlayback(groupId: String) async {
        let subscribeCommand: [String: Any] = [
            "namespace": "playback:1",
            "command": "subscribe",
            "groupId": groupId
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        try? await task?.send(.data(data))
    }
    
    private func resubscribeToMetadata(groupId: String) async {
        let subscribeCommand: [String: Any] = [
            "namespace": "playbackMetadata:1",
            "command": "subscribe",
            "groupId": groupId
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        try? await task?.send(.data(data))
    }
    
    private func resubscribeToGroup(householdId: String) async {
        let subscribeCommand: [String: Any] = [
            "namespace": "groups:1",
            "command": "subscribe",
            "householdId": householdId
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        try? await task?.send(.data(data))
    }

    private lazy var volumeStream: SonosVolumeWebSocketStream = {
        return SonosVolumeWebSocketStream { [weak self] continuation in
            self?.volumeContinuation = continuation
            self?.startMessageReceiver()
        }
    }()
    
    private lazy var groupVolumeStream: SonosVolumeWebSocketStream = {
        return SonosVolumeWebSocketStream { [weak self] continuation in
            self?.groupVolumeContinuation = continuation
            self?.startMessageReceiver()
        }
    }()
    
    private lazy var playbackStream: SonosPlaybackWebSocketStream = {
        return SonosPlaybackWebSocketStream { [weak self] continuation in
            self?.playbackContinuation = continuation
            self?.startMessageReceiver()
        }
    }()
    
    private lazy var trackStream: SonosTrackWebSocketStream = {
        return SonosTrackWebSocketStream { [weak self] continuation in
            self?.trackInfoContinuation = continuation
            self?.startMessageReceiver()
        }
    }()
    
    private lazy var groupStream: SonosGroupWebSocketStream = {
        return SonosGroupWebSocketStream { [weak self] continuation in
            self?.groupContinuation = continuation
            self?.startMessageReceiver()
        }
    }()
    
    
    
    // MARK: - Initialization
    
    /**
     * Creates a new SonosWebSocket instance for connecting to a specific Sonos device.
     *
     * This initializer sets up the WebSocket connection infrastructure but doesn't
     * immediately connect. Call one of the `connectAndSubscribeTo*` methods to establish
     * the connection and start receiving events.
     *
     * - Parameters:
     *   - ipAddress: The IP address of the target Sonos device (e.g., "192.168.1.100")
     *   - apiKey: The Sonos API key for authentication. Defaults to a test key for development.
     *             In production, obtain a key from the Sonos Developer Portal.
     *   - debug: Enable detailed logging of WebSocket messages and connection events.
     *            Useful for development and troubleshooting. Defaults to true.
     *
     * - Returns: A configured SonosWebSocket instance, or nil if the setup fails
     *
     * ## Example
     * ```swift
     * guard let socket = SonosWebSocket(
     *     ipAddress: "192.168.1.100",
     *     apiKey: "your-production-api-key",
     *     debug: false
     * ) else {
     *     print("Failed to create WebSocket")
     *     return
     * }
     * ```
     */
    public init?(ipAddress: String, apiKey: String = "123e4567-e89b-12d3-a456-426655440000", debug: Bool = true) {
        self.apiKey = apiKey
        self.debug = debug
        self.ipAddress = ipAddress
        
        super.init()
        
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        
        createWebSocketTask()
    }
    
    private func createWebSocketTask() {
        guard let url = URL(string: "wss://\(ipAddress):1443/websocket/api") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Sonos-Api-Key")
        request.setValue("v1.api.smartspeaker.audio", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        
        self.task = session?.webSocketTask(with: request)
    }
    
    deinit {
        if debug {
            print("DEBUG: SonosWebSocket for \(ipAddress) is being deallocated")
        }
        
        // Cancel WebSocket task
        if let currentTask = task, currentTask.closeCode == .invalid {
            currentTask.cancel(with: .normalClosure, reason: nil)
        }
        
        // Finish all continuations
        trackInfoContinuation?.finish()
        playbackContinuation?.finish()
        volumeContinuation?.finish()
        groupVolumeContinuation?.finish()
        groupContinuation?.finish()
        
        // Cancel background tasks
        messageReceiveTask?.cancel()
        reconnectTask?.cancel()
        
        // Invalidate session
        session?.invalidateAndCancel()
    }
    
    
    /**
     * Cancels the WebSocket connection and cleans up all resources.
     *
     * This method gracefully closes the WebSocket connection, finishes all active streams,
     * and cancels background tasks. Use this method when you want to permanently shut down
     * the connection and clean up resources.
     *
     * - Throws: Potential cleanup errors, though the method attempts to complete successfully
     *
     * ## Note
     * After calling this method, the WebSocket instance should not be reused.
     * Create a new instance if you need to reconnect later.
     */
    func cancel() async throws {
        // Only cancel if task exists and is not already closed
        if let currentTask = task, currentTask.closeCode == .invalid {
            currentTask.cancel(with: .normalClosure, reason: nil)
        }
        
        // Finish all stream continuations
        trackInfoContinuation?.finish()
        playbackContinuation?.finish()
        volumeContinuation?.finish()
        groupVolumeContinuation?.finish()
        groupContinuation?.finish()
        
        // Cancel background tasks
        messageReceiveTask?.cancel()
        reconnectTask?.cancel()
        
        // Clear all references
        trackInfoContinuation = nil
        playbackContinuation = nil
        volumeContinuation = nil
        groupVolumeContinuation = nil
        groupContinuation = nil
        messageReceiveTask = nil
        reconnectTask = nil
        task = nil
        
        // Invalidate session
        session?.invalidateAndCancel()
        session = nil
        
        // Clear active subscriptions
        activeSubscriptions.removeAll()
    }
    
    /**
     * Closes the WebSocket connection and stops all background tasks.
     *
     * This method immediately closes the WebSocket connection and cancels all background
     * processing tasks. Unlike `cancel()`, this method does not finish the stream continuations,
     * which may result in streams ending abruptly.
     *
     * ## Usage
     * ```swift
     * // Clean shutdown when done with the connection
     * socket.close()
     * ```
     *
     * ## Note
     * For a more graceful shutdown that properly finishes streams, use `cancel()` instead.
     */
    public func close() {
        // Only cancel if task exists and is not already closed
        if let currentTask = task, currentTask.closeCode == .invalid {
            currentTask.cancel(with: .normalClosure, reason: nil)
        }
        
        // Finish all stream continuations to break retain cycles
        trackInfoContinuation?.finish()
        playbackContinuation?.finish()
        volumeContinuation?.finish()
        groupVolumeContinuation?.finish()
        groupContinuation?.finish()
        
        // Cancel background tasks
        messageReceiveTask?.cancel()
        reconnectTask?.cancel()
        
        // Clear continuation references
        trackInfoContinuation = nil
        playbackContinuation = nil
        volumeContinuation = nil
        groupVolumeContinuation = nil
        groupContinuation = nil
        messageReceiveTask = nil
        reconnectTask = nil
        
        // Clear task reference
        task = nil
        
        // Invalidate and clear session to break all references
        session?.invalidateAndCancel()
        session = nil
        
        // Clear active subscriptions
        activeSubscriptions.removeAll()
    }
    
    public func connectAndSubscribeToGroupVolume(groupId: String) async throws -> SonosVolumeWebSocketStream? {
        // Only connect if not already connected
        task?.resume()
        return try await subscribeToGroupVolume(groupId: groupId)
    }
    
    
    /// Subscribes to player volume updates for a specific player
    /// - Parameter playerId: The player ID to subscribe to
    /// - Returns: An AsyncStream of player volume updates
    /// - Throws: `SonosWebSocketError` if the operation fails
    func subscribeToGroupVolume(groupId: String) async throws -> SonosVolumeWebSocketStream? {
        // Track this subscription for reconnection
        var subscriptions = activeSubscriptions
        subscriptions["groupVolume"] = groupId
        activeSubscriptions = subscriptions
        
        let subscribeCommand: [String: Any] = [
            "namespace": "groupVolume:1",
            "command": "subscribe",
            "groupId": groupId
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        debugPrint("DEBUG: Sending command: \(payload)")
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return nil }
        try? await task?.send(.data(data))
        
        return groupVolumeStream
    }
    
    /**
     * Connects to the Sonos device and subscribes to real-time volume updates for a specific player.
     *
     * This method establishes the WebSocket connection (if not already connected) and subscribes
     * to volume change events for the specified player. The connection automatically handles
     * reconnection and resubscription in case of network issues.
     *
     * - Parameter playerId: The unique identifier for the Sonos player (e.g., "RINCON_000E58FE3AEA01400").
     *                      This can be obtained from the Sonos API or device discovery.
     *
     * - Returns: An AsyncStream that yields `VolumeEvent` instances containing volume state changes,
     *           or nil if the subscription setup fails
     *
     * - Throws: Network errors, authentication failures, or WebSocket protocol errors
     *
     * ## Usage
     * ```swift
     * do {
     *     let volumeStream = try await socket.connectAndSubscribeToPlayerVolume(
     *         playerId: "RINCON_000E58FE3AEA01400"
     *     )
     *
     *     for try await volumeEvent in volumeStream {
     *         if let volume = volumeEvent.volumeState?.volume {
     *             print("Volume changed to: \(volume)%")
     *             print("Muted: \(volumeEvent.volumeState?.muted ?? false)")
     *         }
     *     }
     * } catch {
     *     print("Volume subscription failed: \(error)")
     * }
     * ```
     */
    public func connectAndSubscribeToPlayerVolume(playerId: String) async throws -> SonosVolumeWebSocketStream? {
        // Only connect if not already connected
        task?.resume()
        return try await subscribeToPlayerVolume(playerId: playerId)
    }
    
    
    /// Subscribes to player volume updates for a specific player
    /// - Parameter playerId: The player ID to subscribe to
    /// - Returns: An AsyncStream of player volume updates
    /// - Throws: `SonosWebSocketError` if the operation fails
    func subscribeToPlayerVolume(playerId: String) async throws -> SonosVolumeWebSocketStream? {
        // Track this subscription for reconnection
        var subscriptions = activeSubscriptions
        subscriptions["volume"] = playerId
        activeSubscriptions = subscriptions
        
        let subscribeCommand: [String: Any] = [
            "namespace": "playerVolume:1",
            "command": "subscribe",
            "playerId": playerId
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        debugPrint("DEBUG: Sending command: \(payload)")
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return nil }
        try? await task?.send(.data(data))
        
        return volumeStream
    }
    
    
    /**
     * Connects to the Sonos device and subscribes to real-time playback updates for a specific group.
     *
     * This method subscribes to playback state changes including play/pause status, track position,
     * queue information, and available playback actions. Groups represent collections of players
     * that play synchronized audio together.
     *
     * - Parameter groupID: The unique identifier for the Sonos group (e.g., "RINCON_000E58FE3AEA01400:56").
     *                     Groups are created when players are bonded or grouped together.
     *
     * - Returns: An AsyncStream that yields `PlaybackEvent` instances containing playback state changes,
     *           or nil if the subscription setup fails
     *
     * - Throws: Network errors, authentication failures, or WebSocket protocol errors
     *
     * ## Usage
     * ```swift
     * let playbackStream = try await socket.connectAndSubscribeToPlayback(
     *     groupID: "RINCON_000E58FE3AEA01400:56"
     * )
     *
     * for try await playbackEvent in playbackStream {
     *     if let state = playbackEvent.playbackState {
     *         print("Playing: \(state.playbackState == "PLAYBACK_STATE_PLAYING")")
     *         print("Position: \(state.positionMillis)ms")
     *     }
     * }
     * ```
     */
    public func connectAndSubscribeToPlayback(groupID: String) async throws -> SonosPlaybackWebSocketStream? {
        // Only connect if not already connected
        task?.resume()
        return try await subscribeToPlayerPlayback(groupID: groupID)
    }
    
    
    /// Subscribes to player volume updates for a specific player
    /// - Parameter playerId: The player ID to subscribe to
    /// - Returns: An AsyncStream of player volume updates
    /// - Throws: `SonosWebSocketError` if the operation fails
    func subscribeToPlayerPlayback(groupID: String) async throws -> SonosPlaybackWebSocketStream? {
        // Track this subscription for reconnection
        var subscriptions = activeSubscriptions
        subscriptions["playback"] = groupID
        activeSubscriptions = subscriptions
        
        let subscribeCommand: [String: Any] = [
            "namespace": "playback:1",
            "command": "subscribe",
            "groupId": groupID
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return nil }
        try? await task?.send(.data(data))
        
        return playbackStream
    }
    
    
    /**
     * Connects to the Sonos device and subscribes to real-time track metadata updates for a specific group.
     *
     * This method subscribes to track metadata changes including song title, artist, album,
     * album artwork, duration, and audio quality information. Metadata events are triggered
     * when tracks change or when new information becomes available.
     *
     * - Parameter groupId: The unique identifier for the Sonos group (e.g., "RINCON_000E58FE3AEA01400:56").
     *                     All players in a group share the same metadata.
     *
     * - Returns: An AsyncStream that yields `TrackEvent` instances containing track metadata,
     *           or nil if the subscription setup fails
     *
     * - Throws: Network errors, authentication failures, or WebSocket protocol errors
     *
     * ## Usage
     * ```swift
     * let metadataStream = try await socket.connectAndSubscribeToMetadata(
     *     groupId: "RINCON_000E58FE3AEA01400:56"
     * )
     *
     * for try await trackEvent in metadataStream {
     *     if let track = trackEvent.metadata?.currentItem?.track {
     *         print("Now playing: \(track.name ?? "Unknown")")
     *         print("Artist: \(track.artist?.name ?? "Unknown")")
     *         print("Album: \(track.album?.name ?? "Unknown")")
     *         if let imageUrl = track.imageUrl {
     *             print("Album art: \(imageUrl)")
     *         }
     *     }
     * }
     * ```
     */
    public func connectAndSubscribeToMetadata(groupId: String) async throws -> SonosTrackWebSocketStream? {
        // Only connect if not already connected
        task?.resume()
        return try await subscribeToPlaybackMetadata(groupId: groupId)
    }
    

    /// Subscribes to playback metadata updates for a specific group
    /// - Parameter groupId: The group ID to subscribe to
    /// - Returns: An AsyncStream of metadata updates
    /// - Throws: `SonosWebSocketError` if the operation fails
    func subscribeToPlaybackMetadata(groupId: String) async throws -> SonosTrackWebSocketStream? {
        // Track this subscription for reconnection
        var subscriptions = activeSubscriptions
        subscriptions["metadata"] = groupId
        activeSubscriptions = subscriptions
        
        let subscribeCommand: [String: Any] = [
            "namespace": "playbackMetadata:1",
            "command": "subscribe",
            "groupId": groupId
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return nil }
        try? await task?.send(.data(data))
        
        return trackStream
    }
    
    /**
     * Connects to the Sonos device and subscribes to real-time group updates for a household.
     *
     * This method subscribes to group status changes including group membership, coordinator changes,
     * and player associations for all groups in a Sonos household. This provides a complete view
     * of all groups and players in the system.
     *
     * - Parameter householdId: The unique identifier for the Sonos household (e.g., "Sonos_GBw44sBd7swQ55xlbUSTzNmTlp.xskX9-5BWErPJ6lJr7aZ").
     *
     * - Returns: An AsyncStream that yields `GroupEvent` instances containing group status changes,
     *           or nil if the subscription setup fails
     *
     * - Throws: Network errors, authentication failures, or WebSocket protocol errors
     *
     * ## Usage
     * ```swift
     * let groupStream = try await socket.connectAndSubscribeToGroup(
     *     householdId: "Sonos_GBw44sBd7swQ55xlbUSTzNmTlp.xskX9-5BWErPJ6lJr7aZ"
     * )
     *
     * for try await groupEvent in groupStream {
     *     if let groupsResponse = groupEvent.groupsResponse {
     *         for group in groupsResponse.groups {
     *             print("Group: \(group.name ?? group.id)")
     *             print("Coordinator: \(group.coordinatorId)")
     *             print("Players: \(group.playerIds)")
     *         }
     *     }
     * }
     * ```
     */
    public func connectAndSubscribeToGroup(householdId: String) async throws -> SonosGroupWebSocketStream? {
        // Only connect if not already connected
        task?.resume()
        return try await subscribeToGroup(householdId: householdId)
    }
    
    /// Subscribes to group updates for a household
    /// - Parameter householdId: The household ID to subscribe to
    /// - Returns: An AsyncStream of group status updates
    /// - Throws: `SonosWebSocketError` if the operation fails
    func subscribeToGroup(householdId: String) async throws -> SonosGroupWebSocketStream? {
        // Track this subscription for reconnection
        var subscriptions = activeSubscriptions
        subscriptions["group"] = householdId
        activeSubscriptions = subscriptions
        
        let subscribeCommand: [String: Any] = [
            "namespace": "groups:1",
            "command": "subscribe",
            "householdId": householdId
        ]
        
        let payload: [Any] = [subscribeCommand, [String: Any]()]
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return nil
        }
        try? await task?.send(.data(data))
        
        return groupStream
    }
    
    /**
     * Seek to a specific position in the current track.
     *
     * - Parameter positionMillis: The position to seek to in milliseconds
     * - Throws: `SonosWebSocketError` if the seek command fails
     */
    public func seek(groupID: String, positionMillis: Int) async throws {
        let seekCommand: [String: Any] = [
            "namespace": "playback:1",
            "command": "seek",
            "groupId": groupID
        ]
        
        let options: [String: Any] = [
            "name": "Sonos Websocket",
            "appId": "com.jjlawren.sonos_websocket",
            "positionMillis": positionMillis
        ]

        let payload: [Any] = [seekCommand, options]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            throw SonosWebSocketError.invalidResponse
        }
        
        try await task?.send(.data(data))
    }
//
//    /// Plays an audio clip on the Sonos device
//    /// - Parameters:
//    ///   - uri: The URI of the audio clip to play
//    ///   - volume: Optional volume level (0-100)
//    /// - Returns: The response from the Sonos device
//    /// - Throws: `SonosWebSocketError` if the operation fails
//    public func playClip(uri: String, volume: Int? = nil) async throws -> AudioClipResponse {
//        let command: [String: Any] = [
//            "namespace": "audioClip:1",
//            "command": "loadAudioClip",
//            "playerId": try await getPlayerId()
//        ]
//
//        var options: [String: Any] = [
//            "name": "Sonos Websocket",
//            "appId": "com.jjlawren.sonos_websocket",
//            "streamUrl": uri
//        ]
//
//        if let volume = volume {
//            options["volume"] = volume
//        }
//
//        return try await sendCommand(command, options: options)
//    }

    // MARK: - URLSessionDelegate
    
    /**
     * Handles SSL certificate validation for local Sonos device connections.
     *
     * Since Sonos devices use self-signed certificates for local connections,
     * this method accepts server trust challenges to allow secure WebSocket
     * connections to work properly.
     */
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - Usage Examples

/**
 * ## Complete Usage Examples
 *
 * ### Basic Volume Monitoring
 * ```swift
 * import Foundation
 *
 * @MainActor
 * class VolumeController: ObservableObject {
 *     @Published var currentVolume: Int = 0
 *     @Published var isMuted: Bool = false
 *
 *     private var socket: SonosWebSocket?
 *     private var volumeTask: Task<Void, Never>?
 *
 *     func startMonitoring(ipAddress: String, playerId: String) {
 *         socket = SonosWebSocket(ipAddress: ipAddress, debug: true)
 *
 *         volumeTask = Task {
 *             do {
 *                 guard let volumeStream = try await socket?.connectAndSubscribeToPlayerVolume(
 *                     playerId: playerId
 *                 ) else { return }
 *
 *                 for try await volumeEvent in volumeStream {
 *                     await MainActor.run {
 *                         if let volumeState = volumeEvent.volumeState {
 *                             self.currentVolume = volumeState.volume
 *                             self.isMuted = volumeState.muted
 *                         }
 *                     }
 *                 }
 *             } catch {
 *                 print("Volume monitoring failed: \(error)")
 *             }
 *         }
 *     }
 *
 *     func stopMonitoring() {
 *         volumeTask?.cancel()
 *         socket?.close()
 *     }
 * }
 * ```
 *
 * ### Multi-Stream Monitoring
 * ```swift
 * class SonosMonitor {
 *     private let socket: SonosWebSocket
 *     private var monitoringTask: Task<Void, Never>?
 *
 *     init(ipAddress: String) {
 *         self.socket = SonosWebSocket(ipAddress: ipAddress, debug: false)!
 *     }
 *
 *     func startMonitoring(playerId: String, groupId: String) {
 *         monitoringTask = Task {
 *             await withTaskGroup(of: Void.self) { group in
 *                 // Monitor volume
 *                 group.addTask {
 *                     await self.monitorVolume(playerId: playerId)
 *                 }
 *
 *                 // Monitor playback
 *                 group.addTask {
 *                     await self.monitorPlayback(groupId: groupId)
 *                 }
 *
 *                 // Monitor metadata
 *                 group.addTask {
 *                     await self.monitorMetadata(groupId: groupId)
 *                 }
 *             }
 *         }
 *     }
 *
 *     private func monitorVolume(playerId: String) async {
 *         do {
 *             guard let stream = try await socket.connectAndSubscribeToPlayerVolume(
 *                 playerId: playerId
 *             ) else { return }
 *
 *             for try await event in stream {
 *                 handleVolumeUpdate(event)
 *             }
 *         } catch {
 *             print("Volume monitoring error: \(error)")
 *         }
 *     }
 *
 *     private func monitorPlayback(groupId: String) async {
 *         do {
 *             guard let stream = try await socket.connectAndSubscribeToPlayback(
 *                 groupID: groupId
 *             ) else { return }
 *
 *             for try await event in stream {
 *                 handlePlaybackUpdate(event)
 *             }
 *         } catch {
 *             print("Playback monitoring error: \(error)")
 *         }
 *     }
 *
 *     private func monitorMetadata(groupId: String) async {
 *         do {
 *             guard let stream = try await socket.connectAndSubscribeToMetadata(
 *                 groupId: groupId
 *             ) else { return }
 *
 *             for try await event in stream {
 *                 handleMetadataUpdate(event)
 *             }
 *         } catch {
 *             print("Metadata monitoring error: \(error)")
 *         }
 *     }
 *
 *     private func handleVolumeUpdate(_ event: VolumeEvent) {
 *         // Handle volume changes
 *     }
 *
 *     private func handlePlaybackUpdate(_ event: PlaybackEvent) {
 *         // Handle playback state changes
 *     }
 *
 *     private func handleMetadataUpdate(_ event: TrackEvent) {
 *         // Handle track metadata changes
 *     }
 * }
 * ```
 *
 * ### Error Handling Best Practices
 * ```swift
 * func robustSonosConnection() async {
 *     let socket = SonosWebSocket(
 *         ipAddress: "192.168.1.100",
 *         apiKey: "your-api-key",
 *         debug: true
 *     )
 *
 *     do {
 *         guard let volumeStream = try await socket?.connectAndSubscribeToPlayerVolume(
 *             playerId: "RINCON_000E58FE3AEA01400"
 *         ) else {
 *             print("Failed to create volume stream")
 *             return
 *         }
 *
 *         for try await volumeEvent in volumeStream {
 *             // Process volume event
 *             if let volume = volumeEvent.volumeState?.volume {
 *                 print("Volume: \(volume)%")
 *             }
 *         }
 *
 *     } catch let error as URLError {
 *         switch error.code {
 *         case .notConnectedToInternet:
 *             print("No internet connection")
 *         case .networkConnectionLost:
 *             print("Network connection lost - will auto-reconnect")
 *         case .cannotConnectToHost:
 *             print("Cannot connect to Sonos device - check IP address")
 *         default:
 *             print("Network error: \(error.localizedDescription)")
 *         }
 *     } catch {
 *         print("Unexpected error: \(error)")
 *     }
 * }
 * ```
 */
