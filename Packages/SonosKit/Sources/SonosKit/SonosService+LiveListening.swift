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
///
/// Ordered so that when two listeners name the same player with *different*
/// addressing, the winner is deterministic rather than dictionary order —
/// `nowPlaying` last, because it's the one that has to keep working with the app
/// closed.
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

    /// Same socket, ignoring which events are on it — i.e. the addressing that
    /// decides whether the connection has to be rebuilt from scratch.
    func addresses(_ other: LiveSubscription) -> Bool {
        ip == other.ip && playerID == other.playerID && groupID == other.groupID
    }
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

    /// Registers a callback for socket events on `listener`'s player.
    ///
    /// Keyed like the subscriptions themselves, so a second consumer can't
    /// silently replace the first — which a single shared closure would.
    @MainActor
    public func observeLiveUpdates(as listener: LiveListener, _ handler: @escaping (GroupRoom) -> Void) {
        liveUpdateObservers[listener] = handler
    }

    @MainActor
    public func removeLiveUpdateObserver(_ listener: LiveListener) {
        liveUpdateObservers.removeValue(forKey: listener)
    }

    /// Fans a socket event out to the listeners watching that player.
    @MainActor
    func notifyLiveUpdate(for group: GroupRoom) {
        for (listener, subscription) in liveListeners where subscription.playerID == group.coordinatorID {
            liveUpdateObservers[listener]?(group)
        }
    }

    /// Connects the union of what the listeners asked for, and closes anything
    /// nobody wants any more.
    @MainActor
    func reconcileLiveConnections() async {
        guard let streamingService else { return }

        // Merge listeners that happen to target the same coordinator. Iterating
        // `allCases` rather than `liveListeners.values` keeps the merge
        // deterministic: dictionary order is arbitrary, so a group whose id had
        // just changed for one listener and not the other could otherwise be
        // subscribed against either id depending on the run.
        var desired: [String: LiveSubscription] = [:]
        for listener in LiveListener.allCases {
            guard let subscription = liveListeners[listener] else { continue }
            if let existing = desired[subscription.playerID] {
                // Later listeners win the addressing; every listener's events are
                // kept.
                desired[subscription.playerID] = LiveSubscription(
                    ip: subscription.ip,
                    playerID: subscription.playerID,
                    groupID: subscription.groupID,
                    events: existing.events.union(subscription.events)
                )
            } else {
                desired[subscription.playerID] = subscription
            }
        }

        for (playerID, connected) in liveConnections {
            guard let wanted = desired[playerID] else {
                await streamingService.removePlayer(playerID)
                forgetLiveConnection(playerID)
                continue
            }
            // `addPlayer` skips players it already holds, so anything the socket
            // was built with has to be compared here: a widened event set
            // (metadata → metadata + playback), but equally a new group id after
            // speakers were grouped, or a new ip after a DHCP renewal. Comparing
            // events alone left the socket pointed at a group that no longer
            // exists, quietly delivering nothing.
            if wanted != connected {
                await streamingService.removePlayer(playerID)
                liveConnections.removeValue(forKey: playerID)
                // Addressing changed means a different stream of items; the
                // change-detection state belongs to the old one.
                if !wanted.addresses(connected) { forgetLiveItems(playerID) }
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
            liveConnections[playerID] = wanted
        }
    }

    /// Drops every listener and closes their sockets, through the registry so
    /// `liveConnections` can't be left claiming a socket that's gone.
    @MainActor
    public func disconnectAll() async {
        liveListeners.removeAll()
        liveUpdateObservers.removeAll()
        await reconcileLiveConnections()
    }

    @MainActor
    private func forgetLiveConnection(_ playerID: String) {
        liveConnections.removeValue(forKey: playerID)
        forgetLiveItems(playerID)
    }

    /// Change-detection key. The two socket streams speak different id
    /// namespaces, so each gets its own slot per player.
    func liveItemKey(_ source: LiveItemSource, _ playerID: String) -> String {
        "\(source.rawValue):\(playerID)"
    }

    @MainActor
    func forgetLiveItems(_ playerID: String) {
        for source in LiveItemSource.allCases {
            let key = liveItemKey(source, playerID)
            lastLiveItemIDs.removeValue(forKey: key)
            liveTrackRefreshTasks.removeValue(forKey: key)?.cancel()
        }
    }
}
