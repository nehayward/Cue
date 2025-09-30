import Foundation
import os

/**
 * Configuration for a Sonos player connection.
 */
public struct SonosPlayerConfig {
    public let ipAddress: String
    public let playerId: String
    public let groupId: String
    public let name: String?
    public let events: Set<SonosStreamingService.EventType>
    
    public init(ipAddress: String, playerId: String, groupId: String, name: String? = nil, events: Set<SonosStreamingService.EventType> = Set(SonosStreamingService.EventType.allCases)) {
        self.ipAddress = ipAddress
        self.playerId = playerId
        self.groupId = groupId
        self.name = name
        self.events = events
    }
}

/**
 * Protocol for receiving Sonos event callbacks.
 *
 * Implement this protocol to receive real-time updates from Sonos devices.
 * All callback methods are optional and called on the main actor for UI updates.
 */
@MainActor
public protocol SonosEventHandler: AnyObject {
    /// Called when volume changes for a player or group
    func onVolumeUpdate(playerId: String, event: VolumeEvent)
    
    /// Called when playback state changes (play/pause/position)
    func onPlaybackUpdate(playerId: String, event: PlaybackEvent)
    
    /// Called when track metadata changes (song, artist, album, artwork)
    func onMetadataUpdate(playerId: String, event: TrackEvent)
    
    /// Called when connection status changes
    func onConnectionStatusChanged(isConnected: Bool, connectionCount: Int)
    
    /// Called when an error occurs
    func onError(playerId: String, error: Error)
    
    /// Called at regular intervals with updated position when position ticker is enabled and track is playing
    /// This provides smooth position updates between actual Sonos position reports
    /// Default interval is 0.1 seconds (10 times per second) for smooth UI animations
    func onPositionTick(playerId: String, currentPositionMillis: Int, isPlaying: Bool)
}


final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) {
        self.value = value
    }
}

// Default implementations (all optional)
public extension SonosEventHandler {
    func onVolumeUpdate(playerId: String, event: VolumeEvent) {}
    func onPlaybackUpdate(playerId: String, event: PlaybackEvent) {}
    func onMetadataUpdate(playerId: String, event: TrackEvent) {}
    func onConnectionStatusChanged(isConnected: Bool, connectionCount: Int) {}
    func onError(playerId: String, error: Error) {}
    func onPositionTick(playerId: String, currentPositionMillis: Int, isPlaying: Bool) {}
}

/**
 * Lightweight service to manage multiple Sonos WebSocket connections with callback-based events.
 *
 * This service creates and manages WebSocket connections to Sonos devices and forwards
 * all events to your provided event handler. It doesn't maintain any state internally,
 * making it flexible for any use case.
 *
 * ## Usage
 * ```swift
 * class MyEventHandler: SonosEventHandler {
 *     func onVolumeUpdate(playerId: String, event: VolumeEvent) {
 *         print("Volume changed for \(playerId): \(event.volumeState?.volume ?? 0)")
 *     }
 * }
 *
 * let handler = MyEventHandler()
 * let service = SonosStreamingService(eventHandler: handler)
 *
 * let config = SonosPlayerConfig(
 *     ipAddress: "192.168.1.100",
 *     playerId: "RINCON_000E58FE3AEA01400",
 *     groupId: "RINCON_000E58FE3AEA01400:56"
 * )
 *
 * await service.addPlayer(config, events: [.volume, .playback, .metadata])
 * ```
 */
public final class SonosStreamingService: @unchecked Sendable {
    
    /// Event types that can be monitored
    public enum EventType: CaseIterable, Hashable {
        case volume
        case groupVolume
        case playback
        case metadata
    }
    
    private let lock = OSAllocatedUnfairLock()
    private var connections: [String: WeakBox<SonosWebSocket>] = [:]
    private var connectionTasks: [String: Task<Void, Never>] = [:]
    
    // Connection refresh timer management
    private var refreshTask: Task<Void, Never>?
    private var playerConfigs: [String: SonosPlayerConfig] = [:]
    private let connectionRefreshInterval: Duration = .seconds(60 * 1)
    private var isRefreshing: Bool = false
    
    private let apiKey: String
    private let debug: Bool
    private weak var eventHandler: SonosEventHandler?
    
    /**
     * Creates a new SonosStreamingService with the specified event handler.
     *
     * - Parameters:
     *   - eventHandler: Your object that implements SonosEventHandler to receive callbacks
     *   - apiKey: Sonos API key for authentication
     *   - debug: Enable debug logging
     *   - enablePositionTicker: Enable smooth position updates when playing (default: true)
     *   - tickerUpdateInterval: How often to update position in seconds (default: 0.1 for smooth UI)
     */
    public init(eventHandler: SonosEventHandler, apiKey: String = "123e4567-e89b-12d3-a456-426655440000", debug: Bool = true, enablePositionTicker: Bool = true, tickerUpdateInterval: TimeInterval = 0.1) {
        self.eventHandler = eventHandler
        self.apiKey = apiKey
        self.debug = debug
    }
    
    /**
     * Add a player and start monitoring event types specified in the config.
     *
     * - Parameters:
     *   - config: Player configuration with IP address, player ID, group ID, and events to monitor
     */
    public func addPlayer(_ config: SonosPlayerConfig) async {
        let playerId = config.playerId
        
        // Check if player already exists
        let existingSocket = lock.withLock {
            connections[playerId]
        }
        
        if existingSocket != nil {
            if debug {
                print("DEBUG: Player \(playerId) already exists, skipping duplicate creation. Current connections: \(connections.count)")
            }
            return
        }
        
        // Create WebSocket connection
        guard let socket = SonosWebSocket(
            ipAddress: config.ipAddress,
            apiKey: apiKey,
            debug: false
        ) else {
            await notifyError(playerId: playerId, error: NSError(domain: "SonosStreamingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create WebSocket"]))
            return
        }
        
        // Store connection and config
        lock.withLock {
            connections[playerId] =  WeakBox(socket)
            playerConfigs[playerId] = config
        }
   
        // Start monitoring events specified in config
        await startMonitoring(playerId: playerId, config: config, socket: socket, events: config.events)
        
        // Start global connection refresh timer if not already running
        startConnectionRefreshTimer()
        
        // Notify connection status change
        await notifyConnectionStatusChanged()
    }
    
    
    /// Gracefully remove a player without affecting the refresh timer (used during refresh)
    private func gracefulRemovePlayer(_ playerId: String) async {
        // Get tasks and socket to cancel
        let (connectionTask, socket) = lock.withLock {
            (connectionTasks[playerId], connections[playerId])
        }
        
        // Cancel tasks first to stop monitoring loops
        connectionTask?.cancel()
        
        // Wait a brief moment for tasks to finish cancellation
        do {
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            // Ignore cancellation errors
        }
        
        // Close connection gracefully and clear the weak reference
        if let socket = socket {
            socket.value?.close() // This now properly finishes all continuations and clears references
            socket.value = nil // Explicitly clear the weak reference
            if debug {
                print("DEBUG: Closed and cleared socket for player \(playerId)")
            }
        }
        
        // Clean up connection state but preserve player configs for reconnection
        lock.withLock {
            connectionTasks.removeValue(forKey: playerId)
            let removedSocket = connections.removeValue(forKey: playerId)
            if debug && removedSocket != nil {
                print("DEBUG: Removed socket for player \(playerId) from connections dictionary. Remaining: \(connections.count)")
            }
            // Note: Don't remove playerConfigs during graceful disconnect - we need them for reconnection
        }
        
        // Notify connection status change
        await notifyConnectionStatusChanged()
    }
    
    /**
     * Remove a player and stop all monitoring.
     *
     * - Parameter playerId: The player ID to remove
     */
    public func removePlayer(_ playerId: String) async {
        // Get tasks and socket to cancel
        let (connectionTask, socket) = lock.withLock {
            (connectionTasks[playerId], connections[playerId])
        }
        
        // Cancel tasks
        connectionTask?.cancel()
        
        // Close connection and clear weak reference
        if let socket = socket {
            try? await socket.value?.cancel()
            socket.value = nil // Explicitly clear the weak reference
        }
        
        // Clean up
        lock.withLock {
            connectionTasks.removeValue(forKey: playerId)
            let removedSocket = connections.removeValue(forKey: playerId)
            playerConfigs.removeValue(forKey: playerId)
            if debug && removedSocket != nil {
                print("DEBUG: Permanently removed socket for player \(playerId). Remaining connections: \(connections.count)")
            }
        }
        
        // Stop refresh timer if no more players
        if lock.withLock({ connections.isEmpty }) {
            stopConnectionRefreshTimer()
        }
        
        // Notify connection status change
        await notifyConnectionStatusChanged()
    }
    
    /// Start monitoring specified event types for a player
    private func startMonitoring(playerId: String, config: SonosPlayerConfig, socket: SonosWebSocket, events: Set<EventType>) async {
        let task = Task { [weak self] in
            await withTaskGroup { group in
                for eventType in events {
                    switch eventType {
                    case .volume:
                        group.addTask { [weak self] in
                            await self?.monitorVolume(playerId: playerId, socket: socket)
                        }
                    case .groupVolume:
                        group.addTask { [weak self] in
                            await self?.monitorGroupVolume(playerId: playerId, groupId: config.groupId, socket: socket)
                        }
                    case .playback:
                        group.addTask { [weak self] in
                            await self?.monitorPlayback(playerId: playerId, groupId: config.groupId, socket: socket)
                        }
                    case .metadata:
                        group.addTask { [weak self] in
                            await self?.monitorMetadata(playerId: playerId, groupId: config.groupId, socket: socket)
                        }
                    }
                }
            }
        }
        
        lock.withLock {
            connectionTasks[playerId] = task
        }
    }
    
    // MARK: - Event Monitoring
    
    /// Monitor metadata changes and forward to event handler
    private func monitorMetadata(playerId: String, groupId: String, socket: SonosWebSocket) async {
        do {
            guard let stream = try await socket.connectAndSubscribeToMetadata(groupId: groupId) else { return }
            
            for try await event in stream {
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                await handler.onMetadataUpdate(playerId: playerId, event: event)
            }
        } catch {
            await notifyError(playerId: playerId, error: error)
        }
    }
    
    /// Monitor playback changes and forward to event handler
    private func monitorPlayback(playerId: String, groupId: String, socket: SonosWebSocket) async {
        do {
            guard let stream = try await socket.connectAndSubscribeToPlayback(groupID: groupId) else { return }
            
            for try await event in stream {
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                await handler.onPlaybackUpdate(playerId: playerId, event: event)
            }
        } catch {
            await notifyError(playerId: playerId, error: error)
        }
    }
    
    /// Monitor player volume changes and forward to event handler
    private func monitorVolume(playerId: String, socket: SonosWebSocket) async {
        do {
            guard let stream = try await socket.connectAndSubscribeToPlayerVolume(playerId: playerId) else { return }
            
            for try await event in stream {
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                await handler.onVolumeUpdate(playerId: playerId, event: event)
            }
        } catch {
            await notifyError(playerId: playerId, error: error)
        }
    }
    
    /// Monitor group volume changes and forward to event handler
    private func monitorGroupVolume(playerId: String, groupId: String, socket: SonosWebSocket) async {
        do {
            guard let stream = try await socket.connectAndSubscribeToGroupVolume(groupId: groupId) else { return }
            
            for try await event in stream {
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                await handler.onVolumeUpdate(playerId: playerId, event: event)
            }
        } catch {
            await notifyError(playerId: playerId, error: error)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Notify event handler of connection status change
    private func notifyConnectionStatusChanged() async {
        let count = lock.withLock {
            connections.count
        }
        
        // Safely access eventHandler to avoid crashes if it becomes nil
        guard let handler = eventHandler else { return }
        await handler.onConnectionStatusChanged(isConnected: count > 0, connectionCount: count)
    }
    
    /// Notify event handler of an error
    private func notifyError(playerId: String, error: Error) async {
        if debug {
            print("Error for \(playerId): \(error)")
        }
        
        // Safely access eventHandler to avoid crashes if it becomes nil
        guard let handler = eventHandler else { return }
        await handler.onError(playerId: playerId, error: error)
    }
    
    // MARK: - Connection Refresh Timer Management
    
    /// Start a timer that refreshes all connections every 5 minutes
    private func startConnectionRefreshTimer() {
        // Only start if not already running
        guard refreshTask == nil else { return }
        
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self?.connectionRefreshInterval ?? .seconds(5 * 60))
                    await self?.refreshAllConnections()
                } catch {
                    break // Task was cancelled
                }
            }
        }
        
        if debug {
            print("DEBUG: Started connection refresh timer (every \(connectionRefreshInterval.formatted(.units(width: .abbreviated))))")
        }
    }
    
    /// Stop the connection refresh timer
    private func stopConnectionRefreshTimer() {
        refreshTask?.cancel()
        refreshTask = nil
        
        if debug {
            print("DEBUG: Stopped connection refresh timer")
        }
    }
    
    /// Refresh all connections by disconnecting and reconnecting all players
    private func refreshAllConnections() async {
        // Prevent concurrent refresh operations
        let shouldRefresh = lock.withLock {
            guard !isRefreshing else { return false }
            isRefreshing = true
            return true
        }
        
        guard shouldRefresh else {
            if debug {
                print("DEBUG: Refresh already in progress, skipping")
            }
            return
        }
        
        defer {
            lock.withLock {
                isRefreshing = false
            }
        }
        
        if debug {
            print("DEBUG: Refreshing all connections...")
        }
        
        // Get snapshot of current player configurations
        let configsToRefresh = lock.withLock {
            Array(playerConfigs.values)
        }
        
        guard !configsToRefresh.isEmpty else {
            if debug {
                print("DEBUG: No players to refresh")
            }
            return
        }
        
        // Gracefully disconnect all current connections without stopping the refresh timer
        await gracefulDisconnectAll()
        
        // Small delay before reconnecting
        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            return // Task was cancelled
        }
        
        // Reconnect all players using addPlayers
        await addPlayers(configsToRefresh)
        
        if debug {
            print("DEBUG: Connection refresh completed for \(configsToRefresh.count) players")
        }
    }
    
    // MARK: - Public Methods
    
    /**
     * Seek to a specific position in the current track for a player.
     *
     * - Parameters:
     *   - playerId: The player ID to seek
     *   - positionMillis: The position to seek to in milliseconds
     */
    public func seek(playerId: String, positionMillis: Int) async throws {
        let (socket, config) = lock.withLock {
            (connections[playerId], playerConfigs[playerId])
        }
        
        guard let socket = socket,
              let config = config else {
            throw SonosWebSocketError.connectionNotFound
        }
        
        try await socket.value?.seek(groupID: config.groupId, positionMillis: positionMillis)
    }
    
    /// Gracefully disconnect all players without stopping the refresh timer (used during refresh)
    private func gracefulDisconnectAll() async {
        let playerIds = lock.withLock {
            Array(connections.keys)
        }
        
        await withTaskGroup(of: Void.self) { [weak self] group in
            for playerId in playerIds {
                group.addTask {
                    await self?.gracefulRemovePlayer(playerId)
                }
            }
        }
        
        // Additional cleanup to ensure all weak references are cleared
        lock.withLock {
            for (_, weakSocket) in connections {
                weakSocket.value = nil
            }
        }
    }
    
    /// Disconnect all players and clean up
    public func disconnectAll() async {
        let playerIds = lock.withLock {
            Array(connections.keys)
        }
        
        // Stop refresh timer
        stopConnectionRefreshTimer()
        
        await withTaskGroup(of: Void.self) { [weak self] group in
            for playerId in playerIds {
                group.addTask {
                    await self?.removePlayer(playerId)
                }
            }
        }
    }
    
    /// Get count of active connections
    public var connectionCount: Int {
        lock.withLock {
            connections.count
        }
    }
    
    /// Check if any connections are active
    public var isConnected: Bool {
        connectionCount > 0
    }
    
    deinit {
        Task { [weak self] in
            await self?.disconnectAll()
        }
    }
}

// MARK: - Convenience Methods

extension SonosStreamingService {
    /**
     * Add multiple players at once.
     *
     * - Parameters:
     *   - configs: Array of player configurations (each containing their own event types to monitor)
     */
    public func addPlayers(_ configs: [SonosPlayerConfig]) async {
        await withTaskGroup(of: Void.self) { [weak self] group in
            for config in configs {
                group.addTask { [ weak self] in
                    await self?.addPlayer(config)
                }
            }
        }
    }
}

// MARK: - Usage Examples

/**
 * ## Complete Usage Examples
 *
 * ### Basic Event Handler Implementation
 * ```swift
 * @MainActor
 * class MyPlayerController: ObservableObject, SonosEventHandler {
 *     @Published var volume: Int = 0
 *     @Published var isPlaying: Bool = false
 *     @Published var currentTrack: String = ""
 *     @Published var artist: String = ""
 *     @Published var isConnected: Bool = false
 *     @Published var currentPosition: Int = 0 // Smoothly updated every second
 *
 *     private var service: SonosStreamingService?
 *
 *     init() {
 *         // Enable position ticker with 0.1 second updates for smooth UI animation
 *         service = SonosStreamingService(
 *             eventHandler: self,
 *             debug: true,
 *             enablePositionTicker: true,
 *             tickerUpdateInterval: 0.1  // 10 updates per second for smooth progress bars
 *         )
 *     }
 *
 *     func onVolumeUpdate(playerId: String, event: VolumeEvent) {
 *         if let volumeState = event.volumeState {
 *             volume = volumeState.volume
 *             print("Volume changed to \(volume)% for \(playerId)")
 *         }
 *     }
 *
 *     func onPlaybackUpdate(playerId: String, event: PlaybackEvent) {
 *         if let playbackState = event.playbackState {
 *             isPlaying = playbackState.playbackState == "PLAYBACK_STATE_PLAYING"
 *             currentPosition = playbackState.positionMillis
 *             print("Playback state: \(isPlaying ? "Playing" : "Paused")")
 *         }
 *     }
 *
 *     func onMetadataUpdate(playerId: String, event: TrackEvent) {
 *         if let track = event.metadata?.currentItem?.track {
 *             currentTrack = track.name ?? "Unknown"
 *             artist = track.artist?.name ?? "Unknown"
 *             print("Now playing: \(currentTrack) by \(artist)")
 *         }
 *     }
 *
 *     func onPositionTick(playerId: String, currentPositionMillis: Int, isPlaying: Bool) {
 *         // Smooth position updates 10 times per second for buttery smooth progress bars
 *         currentPosition = currentPositionMillis
 *     }
 *
 *     func onConnectionStatusChanged(isConnected: Bool, connectionCount: Int) {
 *         self.isConnected = isConnected
 *         print("Connection status: \(isConnected), count: \(connectionCount)")
 *     }
 *
 *     func onError(playerId: String, error: Error) {
 *         print("Error for \(playerId): \(error.localizedDescription)")
 *     }
 *
 *     func connectToPlayer() async {
 *         let config = SonosPlayerConfig(
 *             ipAddress: "192.168.1.100",
 *             playerId: "RINCON_000E58FE3AEA01400",
 *             groupId: "RINCON_000E58FE3AEA01400:56"
 *         )
 *
 *         // Monitor volume, playback (for position), and metadata
 *         await service?.addPlayer(config, events: [.volume, .playback, .metadata])
 *     }
 * }
 * ```
 *
 * ### Advanced Multi-Player Setup
 * ```swift
 * class SonosHouseController: SonosEventHandler {
 *     private var service: SonosStreamingService
 *     private var playerStates: [String: PlayerState] = [:]
 *
 *     struct PlayerState {
 *         var volume: Int = 0
 *         var isPlaying: Bool = false
 *         var currentTrack: String = ""
 *     }
 *
 *     init() {
 *         service = SonosStreamingService(eventHandler: self)
 *         setupPlayers()
 *     }
 *
 *     private func setupPlayers() {
 *         Task {
 *             let configs = [
 *                 SonosPlayerConfig(
 *                     ipAddress: "192.168.1.100",
 *                     playerId: "RINCON_000E58FE3AEA01400",
 *                     groupId: "RINCON_000E58FE3AEA01400:56",
 *                     name: "Living Room"
 *                 ),
 *                 SonosPlayerConfig(
 *                     ipAddress: "192.168.1.101",
 *                     playerId: "RINCON_000E58FE3AEA01401",
 *                     groupId: "RINCON_000E58FE3AEA01401:57",
 *                     name: "Kitchen"
 *                 )
 *             ]
 *
 *             // Add all players monitoring all event types
 *             await service.addPlayers(configs)
 *         }
 *     }
 *
 *     func onVolumeUpdate(playerId: String, event: VolumeEvent) {
 *         if playerStates[playerId] == nil {
 *             playerStates[playerId] = PlayerState()
 *         }
 *         playerStates[playerId]?.volume = event.volumeState?.volume ?? 0
 *     }
 *
 *     func onMetadataUpdate(playerId: String, event: TrackEvent) {
 *         if playerStates[playerId] == nil {
 *             playerStates[playerId] = PlayerState()
 *         }
 *         playerStates[playerId]?.currentTrack = event.metadata?.currentItem?.track?.name ?? ""
 *     }
 *
 *     func getPlayerState(for playerId: String) -> PlayerState? {
 *         return playerStates[playerId]
 *     }
 * }
 * ```
 *
 * ### Selective Event Monitoring
 * ```swift
 * class VolumeOnlyController: SonosEventHandler {
 *     private var service: SonosStreamingService
 *
 *     init() {
 *         // Disable position ticker for efficiency since we're not monitoring playback
 *         service = SonosStreamingService(eventHandler: self, debug: false, enablePositionTicker: false)
 *     }
 *
 *     func monitorVolumeOnly() async {
 *         let config = SonosPlayerConfig(
 *             ipAddress: "192.168.1.100",
 *             playerId: "RINCON_000E58FE3AEA01400",
 *             groupId: "RINCON_000E58FE3AEA01400:56"
 *         )
 *
 *         // Only monitor volume changes - much more efficient
 *         await service.addPlayer(config, events: [.volume])
 *     }
 *
 *     func onVolumeUpdate(playerId: String, event: VolumeEvent) {
 *         print("Volume: \(event.volumeState?.volume ?? 0)")
 *     }
 *
 *     // Other callbacks not implemented - won't be called
 * }
 * ```
 *
 * ### Position Ticker Control
 * ```swift
 * class PositionAwareController: SonosEventHandler {
 *     @Published var currentPosition: Int = 0
 *     @Published var isPlaying: Bool = false
 *
 *     private var service: SonosStreamingService
 *
 *     init(smoothPositionUpdates: Bool = true) {
 *         service = SonosStreamingService(
 *             eventHandler: self,
 *             enablePositionTicker: smoothPositionUpdates
 *         )
 *     }
 *
 *     func onPlaybackUpdate(playerId: String, event: PlaybackEvent) {
 *         if let playbackState = event.playbackState {
 *             isPlaying = playbackState.playbackState == "PLAYBACK_STATE_PLAYING"
 *             currentPosition = playbackState.positionMillis
 *         }
 *     }
 *
 *     func onPositionTick(playerId: String, currentPositionMillis: Int, isPlaying: Bool) {
 *         // Only called if position ticker is enabled
 *         // Update frequency depends on tickerUpdateInterval setting
 *         currentPosition = currentPositionMillis
 *     }
 * }
 * ```
 *
 * ### Ultra-Smooth UI Animation
 * ```swift
 * @MainActor
 * class SmoothProgressController: ObservableObject, SonosEventHandler {
 *     @Published var progress: Double = 0.0 // 0.0 to 1.0
 *     @Published var currentTime: String = "0:00"
 *     @Published var totalTime: String = "0:00"
 *
 *     private var service: SonosStreamingService
 *     private var totalDuration: Int = 0
 *
 *     init() {
 *         // Ultra-smooth updates at 30fps for buttery smooth progress bars
 *         service = SonosStreamingService(
 *             eventHandler: self,
 *             enablePositionTicker: true,
 *             tickerUpdateInterval: 1.0 / 30.0  // 30 updates per second
 *         )
 *     }
 *
 *     func onMetadataUpdate(playerId: String, event: TrackEvent) {
 *         if let track = event.metadata?.currentItem?.track {
 *             totalDuration = track.durationMillis ?? 0
 *             totalTime = formatTime(milliseconds: totalDuration)
 *         }
 *     }
 *
 *     func onPositionTick(playerId: String, currentPositionMillis: Int, isPlaying: Bool) {
 *         // Update progress 30 times per second for ultra-smooth animation
 *         if totalDuration > 0 {
 *             progress = Double(currentPositionMillis) / Double(totalDuration)
 *         }
 *         currentTime = formatTime(milliseconds: currentPositionMillis)
 *     }
 *
 *     private func formatTime(milliseconds: Int) -> String {
 *         let seconds = milliseconds / 1000
 *         let minutes = seconds / 60
 *         let remainingSeconds = seconds % 60
 *         return String(format: "%d:%02d", minutes, remainingSeconds)
 *     }
 * }
 * ```
 */

