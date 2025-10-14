import Foundation
import os
#if canImport(AppKit)
import AppKit
#endif

/**
 * Configuration for a Sonos player connection.
 */
public struct SonosPlayerConfig {
    public let ipAddress: String
    public let playerId: String
    public let groupId: String
    public let name: String?
    public let householdId: String?
    public let events: Set<SonosStreamingService.EventType>
    
    public init(
        ipAddress: String,
        playerId: String,
        groupId: String,
        name: String? = nil,
        householdId: String? = nil,
        events: Set<SonosStreamingService.EventType> = Set(SonosStreamingService.EventType.allCases)
    ) {
        self.ipAddress = ipAddress
        self.playerId = playerId
        self.groupId = groupId
        self.name = name
        self.householdId = householdId
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
    
    /// Called when group status changes (membership, coordinator)
    func onGroupUpdate(playerId: String, event: GroupEvent)
    
    /// Called when connection status changes
    func onConnectionStatusChanged(isConnected: Bool, connectionCount: Int)
    
    /// Called when an error occurs
    func onError(playerId: String, error: Error)
    
    /// Called at regular intervals with updated position when position ticker is enabled and track is playing
    /// This provides smooth position updates between actual Sonos position reports
    /// Default interval is 0.1 seconds (10 times per second) for smooth UI animations
    func onPositionTick(playerId: String, currentPositionMillis: Int, isPlaying: Bool)
}

// Default implementations (all optional)
public extension SonosEventHandler {
    func onVolumeUpdate(playerId: String, event: VolumeEvent) {}
    func onPlaybackUpdate(playerId: String, event: PlaybackEvent) {}
    func onMetadataUpdate(playerId: String, event: TrackEvent) {}
    func onGroupUpdate(playerId: String, event: GroupEvent) {}
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
@MainActor
public final class SonosStreamingService {
    
    /// Event types that can be monitored
    public enum EventType: CaseIterable, Hashable {
        case volume
        case groupVolume
        case playback
        case metadata
        case group
    }
    
    private var connections: [String: SonosWebSocket] = [:]
    private var connectionTasks: [String: Task<Void, Never>] = [:]
    
    // Connection refresh timer management
    private var refreshTask: Task<Void, Never>?
    private var playerConfigs: [String: SonosPlayerConfig] = [:]
    // Increased from 60s to 5 minutes to reduce refresh churn and memory pressure
    private let connectionRefreshInterval: Duration = .seconds(60 * 5)
    private var isRefreshing: Bool = false
    
    // Group monitoring - only one player can monitor group events at a time
    private var currentGroupMonitoringPlayerId: String?
    
    // Sleep/wake notification observer task
    private var wakeObserverTask: Task<Void, Never>?
    
    private let apiKey: String
    private let debug: Bool
    private weak var eventHandler: SonosEventHandler?
    
    /**
     * Creates a new SonosStreamingService with the specified event handler.
     *
     * - Parameters:
     *   - eventHandler: Your object that implements SonosEventHandler to receive callbacks
     *   - apiKey: Sonos API key for authentication
     *   - debug: Enable debug logging (disabled by default to reduce memory usage)
     *   - enablePositionTicker: Enable smooth position updates when playing (default: true)
     *   - tickerUpdateInterval: How often to update position in seconds (default: 0.1 for smooth UI)
     */
    public init(eventHandler: SonosEventHandler, apiKey: String = "123e4567-e89b-12d3-a456-426655440000", debug: Bool = false, enablePositionTicker: Bool = true, tickerUpdateInterval: TimeInterval = 0.1) {
        self.eventHandler = eventHandler
        self.apiKey = apiKey
        self.debug = debug
        
        // Setup sleep/wake notification listener on macOS
        setupSleepWakeNotifications()
    }
    
    /// Setup notification observers for system sleep/wake events using async streams
    private func setupSleepWakeNotifications() {
        #if canImport(AppKit)
        wakeObserverTask = Task { [weak self] in
            // Use NSWorkspace's notification center instead of default
            let notifications = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didWakeNotification
            )
            
            // Properly handle stream termination to prevent memory accumulation
            for await _ in notifications {
                // Check cancellation and self existence at start of each iteration
                guard let self = self else { 
                    // Self deallocated, exit loop cleanly
                    break 
                }
                
                guard !Task.isCancelled else { 
                    // Task cancelled, exit loop
                    break 
                }
                
                if self.debug {
                    print("DEBUG: Computer woke from sleep, refreshing all connections...")
                }
                
                await self.handleWakeFromSleep()
            }
            
            // Cleanup when loop exits
            if let self = self, self.debug {
                print("DEBUG: Sleep/wake notification stream terminated")
            }
        }
        
        if debug {
            print("DEBUG: Sleep/wake notification stream listener setup")
        }
        #endif
    }
    
    /// Handle system wake from sleep by refreshing all connections
    private func handleWakeFromSleep() async {
        // Refresh all connections after wake
        await refreshAllConnections()
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
        let existingSocket = connections[playerId]
        
        if existingSocket != nil {
            if debug {
                print("DEBUG: Player \(playerId) already exists, skipping duplicate creation. Current connections: \(connections.count)")
            }
            return
        }
        
        // Create WebSocket connection
        // Disable debug in production to reduce memory usage from print statements
        guard let socket = SonosWebSocket(
            ipAddress: config.ipAddress,
            apiKey: apiKey,
            debug: false
        ) else {
            await notifyError(playerId: playerId, error: NSError(domain: "SonosStreamingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create WebSocket"]))
            return
        }
        
        // Store connection and config
        connections[playerId] = socket
        playerConfigs[playerId] = config
        
   
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
        let connectionTask = connectionTasks[playerId]
        let socket = connections[playerId]
        
        // Cancel tasks first to stop monitoring loops
        connectionTask?.cancel()
        
        // Wait a brief moment for tasks to finish cancellation
        // This allows AsyncStreams and continuations to properly terminate
        try? await Task.sleep(for: .milliseconds(100))
        
        // Close connection gracefully - this releases URLSession and all resources
        if let socket = socket {
            socket.close() // This properly finishes all continuations and clears references
            if debug {
                print("DEBUG: Closed socket for player \(playerId)")
            }
        }
        
        // Clean up connection state but preserve player configs for reconnection
        connectionTasks.removeValue(forKey: playerId)
        let removedSocket = connections.removeValue(forKey: playerId)
        if debug && removedSocket != nil {
            print("DEBUG: Removed socket for player \(playerId) from connections dictionary. Remaining: \(connections.count)")
        }
        
        // Clear group monitoring if this player was monitoring groups
        if currentGroupMonitoringPlayerId == playerId {
            currentGroupMonitoringPlayerId = nil
            if debug {
                print("DEBUG: Cleared group monitoring for removed player \(playerId)")
            }
        }
        // Note: Don't remove playerConfigs during graceful disconnect - we need them for reconnection
        
        // Additional wait to ensure URLSession invalidation completes
        // This prevents accumulation of URLSession instances
        try? await Task.sleep(for: .milliseconds(50))
        
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
        let connectionTask = connectionTasks[playerId]
        let socket = connections[playerId]
        
        // Cancel tasks
        connectionTask?.cancel()
        
        // Wait a brief moment for cancellation
        try? await Task.sleep(for: .milliseconds(100))
        
        // Close connection
        if let socket = socket {
            socket.close()
        }
        
        // Clean up
        connectionTasks.removeValue(forKey: playerId)
        let removedSocket = connections.removeValue(forKey: playerId)
        playerConfigs.removeValue(forKey: playerId)
        if debug && removedSocket != nil {
            print("DEBUG: Permanently removed socket for player \(playerId). Remaining connections: \(connections.count)")
        }
        
        // Clear group monitoring if this player was monitoring groups
        if currentGroupMonitoringPlayerId == playerId {
            currentGroupMonitoringPlayerId = nil
            if debug {
                print("DEBUG: Cleared group monitoring for permanently removed player \(playerId)")
            }
        }
        
        // Stop refresh timer if no more players
        if connections.isEmpty {
            stopConnectionRefreshTimer()
        }
        
        // Notify connection status change
        await notifyConnectionStatusChanged()
    }
    
    /// Start monitoring specified event types for a player
    private func startMonitoring(playerId: String, config: SonosPlayerConfig, socket: SonosWebSocket, events: Set<EventType>) async {
        // Capture config values to avoid accessing potentially deallocated struct
        let groupId = config.groupId
        let householdId = config.householdId
        
        let task = Task { [weak self, weak socket] in
            guard let self = self, let socket = socket else { return }
            
            await withTaskGroup(of: Void.self) { group in
                for eventType in events {
                    switch eventType {
                    case .volume:
                        group.addTask { [weak self, weak socket] in
                            guard let self = self, let socket = socket else { return }
                            await self.monitorVolume(playerId: playerId, socket: socket)
                        }
                    case .groupVolume:
                        group.addTask { [weak self, weak socket] in
                            guard let self = self, let socket = socket else { return }
                            await self.monitorGroupVolume(playerId: playerId, groupId: groupId, socket: socket)
                        }
                    case .playback:
                        group.addTask { [weak self, weak socket] in
                            guard let self = self, let socket = socket else { return }
                            await self.monitorPlayback(playerId: playerId, groupId: groupId, socket: socket)
                        }
                    case .metadata:
                        group.addTask { [weak self, weak socket] in
                            guard let self = self, let socket = socket else { return }
                            await self.monitorMetadata(playerId: playerId, groupId: groupId, socket: socket)
                        }
                    case .group:
                        // Only allow one player to monitor group events at a time
                        // householdId is required for group monitoring
                        if let householdId = householdId {
                            // Check if we should monitor groups before creating the task
                            group.addTask { [weak self, weak socket] in
                                guard let self = self, let socket = socket else { return }
                                
                                // Double-check monitoring eligibility inside the task
                                guard await self.shouldStartGroupMonitoring(for: playerId) else { return }
                                
                                await self.monitorGroup(playerId: playerId, householdId: householdId, socket: socket)
                            }
                        }
                    }
                }
            }
        }
        
        connectionTasks[playerId] = task
    }
    
    // MARK: - Event Monitoring
    
    /// Check if group monitoring should start for this player (only one at a time)
    private func shouldStartGroupMonitoring(for playerId: String) async -> Bool {
        if let currentId = currentGroupMonitoringPlayerId {
            if currentId == playerId {
                // Same player, allow
                return true
            } else {
                // Different player already monitoring
                if debug {
                    print("DEBUG: Group monitoring already active for player \(currentId), skipping for \(playerId)")
                }
                return false
            }
        } else {
            // No one monitoring, start
            currentGroupMonitoringPlayerId = playerId
            if debug {
                print("DEBUG: Starting group monitoring for player \(playerId)")
            }
            return true
        }
    }
    
    /// Monitor metadata changes and forward to event handler
    private func monitorMetadata(playerId: String, groupId: String, socket: SonosWebSocket) async {
        do {
            guard let stream = try await socket.connectAndSubscribeToMetadata(groupId: groupId) else { return }
            
            for try await event in stream {
                // Check if task was cancelled
                if Task.isCancelled { break }
                
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                handler.onMetadataUpdate(playerId: playerId, event: event)
            }
        } catch {
            if !Task.isCancelled {
                await notifyError(playerId: playerId, error: error)
            }
        }
    }
    
    /// Monitor playback changes and forward to event handler
    private func monitorPlayback(playerId: String, groupId: String, socket: SonosWebSocket) async {
        do {
            guard let stream = try await socket.connectAndSubscribeToPlayback(groupID: groupId) else { return }
            
            for try await event in stream {
                // Check if task was cancelled
                if Task.isCancelled { break }
                
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                handler.onPlaybackUpdate(playerId: playerId, event: event)
            }
        } catch {
            if !Task.isCancelled {
                await notifyError(playerId: playerId, error: error)
            }
        }
    }
    
    /// Monitor player volume changes and forward to event handler
    private func monitorVolume(playerId: String, socket: SonosWebSocket) async {
        do {
            guard let stream = try await socket.connectAndSubscribeToPlayerVolume(playerId: playerId) else { return }
            
            for try await event in stream {
                // Check if task was cancelled
                if Task.isCancelled { break }
                
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                handler.onVolumeUpdate(playerId: playerId, event: event)
            }
        } catch {
            if !Task.isCancelled {
                await notifyError(playerId: playerId, error: error)
            }
        }
    }
    
    /// Monitor group volume changes and forward to event handler
    private func monitorGroupVolume(playerId: String, groupId: String, socket: SonosWebSocket) async {
        do {
            guard let stream = try await socket.connectAndSubscribeToGroupVolume(groupId: groupId) else { return }
            
            for try await event in stream {
                // Check if task was cancelled
                if Task.isCancelled { break }
                
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                handler.onVolumeUpdate(playerId: playerId, event: event)
            }
        } catch {
            if !Task.isCancelled {
                await notifyError(playerId: playerId, error: error)
            }
        }
    }
    
    /// Monitor group status changes and forward to event handler (only one player at a time)
    private func monitorGroup(playerId: String, householdId: String, socket: SonosWebSocket) async {
        // Capture debug flag to avoid accessing self in defer if deallocated
        let shouldDebug = debug
        
        defer {
            // Clear group monitoring when done
            // Safe to access self here since defer runs before method returns
            if currentGroupMonitoringPlayerId == playerId {
                currentGroupMonitoringPlayerId = nil
                if shouldDebug {
                    print("DEBUG: Stopped group monitoring for player \(playerId)")
                }
            }
        }
        
        do {
            guard let stream = try await socket.connectAndSubscribeToGroup(householdId: householdId) else { return }
            
            for try await event in stream {
                // Check if task was cancelled
                if Task.isCancelled { break }
                
                // Safely access eventHandler to avoid crashes if it becomes nil
                guard let handler = eventHandler else { break }
                handler.onGroupUpdate(playerId: playerId, event: event)
            }
        } catch {
            if !Task.isCancelled {
                await notifyError(playerId: playerId, error: error)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Notify event handler of connection status change
    private func notifyConnectionStatusChanged() async {
        let count = connections.count
        
        // Safely access eventHandler to avoid crashes if it becomes nil
        guard let handler = eventHandler else { return }
        handler.onConnectionStatusChanged(isConnected: count > 0, connectionCount: count)
    }
    
    /// Notify event handler of an error
    private func notifyError(playerId: String, error: Error) async {
        if debug {
            print("Error for \(playerId): \(error)")
        }
        
        // Safely access eventHandler to avoid crashes if it becomes nil
        guard let handler = eventHandler else { return }
        handler.onError(playerId: playerId, error: error)
    }
    
    // MARK: - Connection Refresh Timer Management
    
    /// Start a timer that refreshes all connections every 5 minutes
    private func startConnectionRefreshTimer() {
        // Only start if not already running
        guard refreshTask == nil else { return }
        
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // Check if self still exists at the start of each loop
                do {
                    try await Task.sleep(for: self?.connectionRefreshInterval ?? .seconds(1 * 60))
                    
                    // Check again after sleep - service might have been deallocated
                    guard let self = self else { break }
                    await self.refreshAllConnections()
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
        var shouldRefresh: Bool {
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
            isRefreshing = false
        }
        
        if debug {
            print("DEBUG: Refreshing all connections...")
        }
        
        // Get snapshot of current player configurations
        let configsToRefresh = Array(playerConfigs.values)
        
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
        let socket = connections[playerId]
        let config = playerConfigs[playerId]
        
        guard let socket = socket,
              let config = config else {
            throw SonosWebSocketError.connectionNotFound
        }
        
        // Capture groupId to avoid accessing config after potential deallocation during async call
        let groupId = config.groupId
        try await socket.seek(groupID: groupId, positionMillis: positionMillis)
    }
    
    /// Gracefully disconnect all players without stopping the refresh timer (used during refresh)
    private func gracefulDisconnectAll() async {
        let playerIds = Array(connections.keys)
        
        await withTaskGroup(of: Void.self) { [weak self] group in
            for playerId in playerIds {
                group.addTask {
                    await self?.gracefulRemovePlayer(playerId)
                }
            }
        }
    }
    
    /// Disconnect all players and clean up
    public func disconnectAll() async {
        let playerIds = Array(connections.keys)
        
        
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
        connections.count
    }
    
    /// Check if any connections are active
    public var isConnected: Bool {
        connectionCount > 0
    }
    
    deinit {
        // Cancel sleep/wake notification observer task
        // This ensures the notification stream terminates immediately
        wakeObserverTask?.cancel()
        wakeObserverTask = nil
        
        // Cancel refresh timer
        refreshTask?.cancel()
        refreshTask = nil
        
        // Cancel all connection tasks synchronously
        for task in connectionTasks.values {
            task.cancel()
        }
        connectionTasks.removeAll()
        
        // Close all sockets synchronously to release URLSession resources
        for socket in connections.values {
            socket.close()
        }
        connections.removeAll()
        
        // Clear all configs and monitoring state
        playerConfigs.removeAll()
        currentGroupMonitoringPlayerId = nil
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

