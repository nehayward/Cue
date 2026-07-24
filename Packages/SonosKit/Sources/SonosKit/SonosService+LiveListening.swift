import Foundation

/// Who asked for a live socket, and for which player.
///
/// Sonos WebSocket connections are the expensive resource here — one socket per
/// speaker, held open — so the app keeps as few as it can get away with. Before
/// this, the only caller (`LargePlayerView`) simply called `disconnectAll()` and
/// re-subscribed to whatever it was showing. That breaks as soon as a second
/// caller wants a socket for a *different* group: the Lock Screen Now Playing
/// card follows the playing group, which isn't always the one on screen.
///
/// So subscriptions are keyed by listener. Each listener declares the player and
/// event types it needs; `reconcileLiveConnections()` connects the union and
/// nothing more.
public enum LiveListener: String, Hashable, Sendable, CaseIterable {
    /// The group currently on screen — metadata only (audio quality badge).
    case viewing
    /// The group backing the system Now Playing card. Survives backgrounding.
    case nowPlaying
}

/// A listener's desired socket: which player, over which group, for what events.
public struct LiveSubscription: Equatable {
    public let ip: String
    public let playerID: String
    public let groupID: String
    public let events: Set<SonosStreamingService.EventType>
}

extension SonosService {
    /// Opens (or re-points) `listener`'s live socket at `group`.
    ///
    /// Idempotent: re-declaring the same player and event set is a no-op, so
    /// this is safe to call from a `.task(id:)` that re-fires on unrelated
    /// state.
    @MainActor
    public func listen(
        to group: GroupRoom,
        as listener: LiveListener,
        events: Set<SonosStreamingService.EventType>
    ) async {
        await listen(
            ip: group.ip,
            playerID: group.coordinatorID,
            groupID: group.id,
            as: listener,
            events: events
        )
    }

    @MainActor
    public func listen(
        ip: String,
        playerID: String,
        groupID: String,
        as listener: LiveListener,
        events: Set<SonosStreamingService.EventType>
    ) async {
        let subscription = LiveSubscription(ip: ip, playerID: playerID, groupID: groupID, events: events)
        guard liveListeners[listener] != subscription else { return }
        liveListeners[listener] = subscription
        await reconcileLiveConnections()
    }

    /// Drops `listener`'s claim. The underlying socket only closes if no other
    /// listener still wants it.
    @MainActor
    public func stopListening(as listener: LiveListener) async {
        guard liveListeners.removeValue(forKey: listener) != nil else { return }
        await reconcileLiveConnections()
    }

    /// Connects the union of what the listeners asked for, and closes anything
    /// nobody wants any more.
    @MainActor
    func reconcileLiveConnections() async {
        guard let streamingService else { return }

        // Merge listeners that happen to target the same coordinator.
        var desired: [String: LiveSubscription] = [:]
        for subscription in liveListeners.values {
            if let existing = desired[subscription.playerID] {
                desired[subscription.playerID] = LiveSubscription(
                    ip: existing.ip,
                    playerID: existing.playerID,
                    groupID: existing.groupID,
                    events: existing.events.union(subscription.events)
                )
            } else {
                desired[subscription.playerID] = subscription
            }
        }

        for (playerID, connectedEvents) in liveConnections {
            guard let wanted = desired[playerID] else {
                await streamingService.removePlayer(playerID)
                liveConnections.removeValue(forKey: playerID)
                lastLiveItemIDs.removeValue(forKey: playerID)
                liveTrackRefreshTasks.removeValue(forKey: playerID)?.cancel()
                continue
            }
            // `addPlayer` skips players it already holds, so a widened event set
            // (metadata → metadata + playback) needs the socket rebuilt.
            if wanted.events != connectedEvents {
                await streamingService.removePlayer(playerID)
                liveConnections.removeValue(forKey: playerID)
            }
        }

        for (playerID, wanted) in desired where liveConnections[playerID] == nil {
            await streamingService.addPlayer(
                .init(
                    ipAddress: wanted.ip,
                    playerId: wanted.playerID,
                    groupId: wanted.groupID,
                    events: wanted.events
                )
            )
            liveConnections[playerID] = wanted.events
        }
    }

    /// Clears every listener and closes all sockets.
    @MainActor
    func clearLiveListeners() {
        liveListeners.removeAll()
        liveConnections.removeAll()
        lastLiveItemIDs.removeAll()
        for task in liveTrackRefreshTasks.values { task.cancel() }
        liveTrackRefreshTasks.removeAll()
    }
}
