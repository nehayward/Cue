import CloudStorage
import Foundation
import Network
import os
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
#endif

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
    /// Legacy `sonos_ip` key. The main app's source of truth is now
    /// `knownHouseholds`, but we still MIRROR the active household's IP here
    /// (write-only) so external consumers that read this key directly — Cue Mini
    /// and the Watch app — keep following the active system. Also read once on
    /// first launch to migrate a pre-household install (see getFirstIP).
    @CloudStorage("sonos_ip") var legacyIP = ""

    /// CloudStorage persists only primitives and `RawRepresentable` values — it has
    /// no `Codable` overload in any released version — so the collections below are
    /// held as JSON strings and surfaced through computed properties. Cue Mini
    /// reads `sonos_known_households` straight out of the key-value store, so this
    /// encoding is load-bearing for that app too.
    @CloudStorage("sonos_known_households") private var knownHouseholdsJSON = ""
    @CloudStorage("sonos_removed_households") private var removedHouseholdsJSON = ""

    var knownHouseholds: [SonosHousehold] {
        get { Self.decode([SonosHousehold].self, from: knownHouseholdsJSON) ?? [] }
        set { knownHouseholdsJSON = Self.encode(newValue) ?? knownHouseholdsJSON }
    }

    /// Households the user explicitly removed. Kept in the SAME synced store as
    /// `knownHouseholds` (not device-local UserDefaults) so it is visible to the
    /// widget/intent extension processes that also run getGroups — otherwise they
    /// would re-adopt a deleted home and write it back into the synced list — and
    /// so a deletion on one device doesn't get resurrected by another.
    var removedHouseholds: [String] {
        get { Self.decode([String].self, from: removedHouseholdsJSON) ?? [] }
        set { removedHouseholdsJSON = Self.encode(newValue) ?? removedHouseholdsJSON }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Returns nil rather than an empty string on failure, so a value that cannot
    /// be encoded leaves the stored one intact instead of wiping every household.
    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    /// The speaker the user explicitly chose to run system-wide lookups through.
    /// Deliberately SEPARATE from `legacyIP`/`lastKnownIP`: those answer "an
    /// address that reaches this household" and are rewritten by the reconnect
    /// race in `getGroups` whenever another speaker replies first. A user's pick
    /// has to outlive that, so it gets its own key that only explicit action writes.
    @CloudStorage("sonos_preferred_speaker_ip") var preferredSpeakerIP = ""
}

@Observable
final class SonosSystemDiscoverService {
    var isSearching: Bool = false
    var currentWakes: Set<String> = []
    /// True while this device has no Wi‑Fi or wired network, only cellular
    /// (or nothing). Speakers are only ever on the local network, so they
    /// can't be reached then. Leaving Wi‑Fi counts after `cellularGrace`.
    var isCellular: Bool = false
    /// Called on the main actor when `isCellular` changes.
    @ObservationIgnored var onCellularChange: (@MainActor (Bool) -> Void)?
    /// Whether the first path has been read. That one counts at once.
    @ObservationIgnored private var hasReadPath = false
    /// When Wi‑Fi went, while the grace runs. Kept across path updates, so
    /// a cellular path changing again doesn't start the grace over.
    @ObservationIgnored private var leftLocalNetworkAt: ContinuousClock.Instant?
    /// When the app last came back to the foreground. A suspended app reads
    /// no paths, so one read on the way back may have changed long before.
    @ObservationIgnored private var resumedAt: ContinuousClock.Instant?
    @ObservationIgnored private var foregroundTask: Task<Void, Never>?
    /// How long Wi‑Fi has to stay gone before it counts. It drops for a
    /// moment at the edge of its range or while roaming, and the speakers
    /// shouldn't leave the screen and come back each time.
    private static let cellularGrace: Duration = .seconds(5)
    var preferredHouseHold: String? {
        get {
            UserDefaults.standard.string(forKey: "cue.household")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "cue.household")
        }
    }

    /// Households the user explicitly removed. Blocked IDs are never auto-recorded
    /// or auto-adopted, so a home you delete while standing in front of it doesn't
    /// reappear on the next pulse or screen revisit. Backed by synced CloudStorage
    /// (see SonosStorageIP.removedHouseholds) so extensions and other devices honour
    /// it too. Cleared per-household by an explicit re-add (switch or manual scan).
    var removedHouseholdIDs: Set<String> {
        get { Set(sonosStorageIP.removedHouseholds) }
        set { sonosStorageIP.removedHouseholds = Array(newValue) }
    }

    func isBlocked(_ id: String) -> Bool { removedHouseholdIDs.contains(id) }

    @MainActor
    func blockHousehold(id: String) {
        var ids = removedHouseholdIDs
        ids.insert(id)
        removedHouseholdIDs = ids
    }

    @MainActor
    func unblockHousehold(id: String) {
        var ids = removedHouseholdIDs
        ids.remove(id)
        removedHouseholdIDs = ids
    }

    var knownHouseholds: [SonosHousehold] {
        get { sonosStorageIP.knownHouseholds }
        set { sonosStorageIP.knownHouseholds = newValue }
    }

    /// The speaker the user picked for system-wide lookups (groups, artwork,
    /// library). Empty means "no preference — use the automatic heuristic".
    var preferredSpeakerIP: String { sonosStorageIP.preferredSpeakerIP }

    /// Sets the explicit speaker choice, or clears it back to the automatic pick
    /// when passed an empty string. Only user actions call this, so the reconnect
    /// race can never overwrite it the way it overwrites `lastKnownIP`. Re-mirrors
    /// so Cue Mini and the Watch follow the choice too.
    @MainActor
    func setPreferredSpeaker(_ ip: String) {
        guard sonosStorageIP.preferredSpeakerIP != ip else { return }
        sonosStorageIP.preferredSpeakerIP = ip
        mirrorLegacyIP()
    }

    /// Known households ordered most-recently-connected first — the order the
    /// Households list shows and the tiebreak `activeHousehold` uses when unpinned,
    /// kept in one place so the list order and the active pick can't diverge.
    var householdsByRecency: [SonosHousehold] {
        knownHouseholds.sorted { $0.lastConnected > $1.lastConnected }
    }

    /// The household currently being monitored, or the most recently connected
    /// one when no explicit preference is set. Falls back to recency when the
    /// pinned household is no longer known — e.g. it was removed on another device
    /// and the removal synced — so a stale pin can't strand this device with no
    /// active system.
    var activeHousehold: SonosHousehold? {
        if let id = preferredHouseHold,
           let pinned = knownHouseholds.first(where: { $0.id == id }) {
            return pinned
        }
        return householdsByRecency.first
    }

    /// IP to use for the fast-path (no discovery needed). Derived from the
    /// active household so there is a single source of truth.
    var cachedIP: String { activeHousehold?.lastKnownIP ?? "" }

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
    // Guards the shared NWBrowser/allIPs/connections state so the reconnect
    // discovery and the Households-screen scan don't run concurrent browses that
    // reset each other mid-flight. Ownership-tracked + cancellation-aware (see
    // acquireExclusiveBrowse) so it can never deadlock.
    @ObservationIgnored private var browseBusy = false
    private var householdIDCache: [String: (id: String, timestamp: Date)] = [:] // IP -> (HouseholdID, Timestamp)

    var lastKnownIP: String = ""
    var lastKnownState: String = ""

    init() {
        cellularMonitor.pathUpdateHandler = { [weak self] path in
            // Determine whether a local-network interface (Wi-Fi or wired
            // Ethernet) is available, rather than asking whether the cellular
            // interface is in use.
            //
            // `path.usesInterfaceType(.cellular)` reports true whenever the
            // cellular interface participates in the path. With Wi-Fi Assist
            // enabled, iOS keeps both the Wi-Fi and cellular interfaces active
            // at the same time, so that check returns true even when Wi-Fi is
            // connected and Sonos is reachable on the local network. That made
            // the app incorrectly report "On Cellular" and refuse to connect.
            //
            // Instead, only treat the device as cellular-only when no Wi-Fi or
            // wired interface is available at all. Sonos devices are reachable
            // over either, so the presence of one means discovery can proceed.
            let localInterfaceTypes: Set<NWInterface.InterfaceType> = [.wifi, .wiredEthernet]
            let hasLocalInterface = path.availableInterfaces
                .map(\.type)
                .contains(where: localInterfaceTypes.contains)
            self?.cellularUpdateTask?.cancel()
            self?.cellularUpdateTask = Task { @MainActor [weak self] in
                await self?.updateCellular(!hasLocalInterface)
            }
        }
        cellularMonitor.start(queue: DispatchQueue(label: "CellularMonitor"))
        #if os(iOS) && !targetEnvironment(macCatalyst)
        foregroundTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                self?.appResumed()
            }
        }
        #endif
    }

    /// Back from the background. A path read now counts at once, and so
    /// does one read on the way back that is waiting out the grace.
    @MainActor
    private func appResumed() {
        resumedAt = ContinuousClock.now
        guard leftLocalNetworkAt != nil, !isCellular else { return }
        cellularUpdateTask?.cancel()
        cellularUpdateTask = Task { @MainActor [weak self] in
            await self?.updateCellular(true)
        }
    }

    /// Wi‑Fi coming back counts at once. Leaving it counts once it has
    /// been gone for `cellularGrace`, unless the app has only just come
    /// back to the foreground; a newer path cancels the wait.
    @MainActor
    private func updateCellular(_ cellular: Bool) async {
        if !cellular {
            leftLocalNetworkAt = nil
        } else if hasReadPath, !isCellular {
            let left = leftLocalNetworkAt ?? ContinuousClock.now
            leftLocalNetworkAt = left
            let justResumed = resumedAt.map { ContinuousClock.now - $0 < Self.cellularGrace } ?? false
            if !justResumed {
                try? await Task.sleep(until: left + Self.cellularGrace, clock: .continuous)
                guard !Task.isCancelled else { return }
            }
        }
        hasReadPath = true
        guard cellular != isCellular else { return }
        isCellular = cellular
        onCellularChange?(cellular)
    }

    deinit {
        stopBrowsing()
        cellularUpdateTask?.cancel()
        foregroundTask?.cancel()
        cellularMonitor.cancel()
        lock.withLock {
            connections.forEach { $0?.cancel() }
            connections.removeAll()
        }
    }

    // Ownership-tracked gate around the shared browser state (browser/allIPs/
    // connections). Returns true only if THIS caller acquired it; the caller must
    // release iff it acquired. The wait bound (12s) is deliberately longer than the
    // longest browse it guards (performDiscovery caps at 10s, getAllIPs at 8s) so a
    // legitimate holder is waited out rather than stomped mid-scan. On cancellation
    // it returns false WITHOUT acquiring, so a cancelled non-owner never releases a
    // gate a real holder still owns. It can't deadlock: browses are self-bounded and
    // release via defer; the 12s ceiling is only a stuck-holder backstop.
    @MainActor
    private func acquireExclusiveBrowse() async -> Bool {
        var waited = 0
        while browseBusy {
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(50))
            waited += 50
            if waited >= 12000 { break }
        }
        if Task.isCancelled { return false }
        browseBusy = true
        return true
    }

    @MainActor
    private func releaseExclusiveBrowse() {
        browseBusy = false
    }

    // Publishes `mirroredIP` to the legacy `sonos_ip` key, which Cue Mini and the
    // Watch read directly. The main app itself only reads it for first-launch
    // migration. No-op when unchanged.
    @MainActor
    private func mirrorLegacyIP() {
        let ip = mirroredIP
        if sonosStorageIP.legacyIP != ip { sonosStorageIP.legacyIP = ip }
    }

    /// The address external consumers should follow: the user's pinned speaker
    /// when it belongs to the active household, otherwise that household's last
    /// known address, and empty when no household remains (so removing the active
    /// home doesn't leave Mini and the Watch aimed at a deleted system).
    ///
    /// Both conditions earn their place. Without the pin those consumers kept
    /// following whichever speaker won the reconnect race while the main app used
    /// the chosen one; without the household gate, a pin left over from a
    /// different home would aim them at a system the main app isn't even on.
    private var mirroredIP: String {
        guard let household = activeHousehold else { return "" }
        let pinned = sonosStorageIP.preferredSpeakerIP
        if !pinned.isEmpty, household.knownIPs.contains(pinned) { return pinned }
        return household.lastKnownIP
    }

    // Re-mirror after a mutation that changes the active household without going
    // through record/switch (i.e. removeHousehold).
    @MainActor
    func refreshLegacyMirror() {
        mirrorLegacyIP()
    }

    // Directly pins a raw IP into the legacy key. Used by manual Connect-by-IP as
    // a discovery-independent bootstrap: getFirstIP falls back to this so a
    // hand-entered IP connects even when household identity can't be resolved and
    // Bonjour is blocked.
    @MainActor
    func pinLegacyIP(_ ip: String) {
        if sonosStorageIP.legacyIP != ip { sonosStorageIP.legacyIP = ip }
    }

    // Household ID for an IP with a 2s timeout + short cache. The reconnect race
    // uses this (not the raw api call) so a device that serves getGroups but stalls
    // on its household endpoint can't hold the race open for the full URLSession
    // timeout.
    func householdID(for ip: String) async -> String {
        await getHouseholdIDWithCache(for: ip)
    }

    // Records or updates a household in the persistent known-households list.
    // Accumulates all known IPs so the race in getGroups can probe them all.
    // Skips households the user explicitly removed so they don't silently return.
    @MainActor
    private func recordHousehold(id: String, ip: String) {
        guard !isBlocked(id) else { return }
        var households = knownHouseholds
        if let idx = households.firstIndex(where: { $0.id == id }) {
            let unchanged = households[idx].lastKnownIP == ip && households[idx].knownIPs.contains(ip)
            guard !unchanged else { return }
            households[idx].lastKnownIP = ip
            households[idx].knownIPs.insert(ip)
            households[idx].lastConnected = .now
        } else {
            // Use the highest ordinal seen so far to avoid re-using a name after removal.
            let maxOrdinal = households.compactMap { h -> Int? in
                if h.name == "Home" { return 1 }
                guard h.name.hasPrefix("Home "), let n = Int(h.name.dropFirst(5)) else { return nil }
                return n
            }.max() ?? 0
            let next = maxOrdinal + 1
            let name = next == 1 ? "Home" : "Home \(next)"
            households.append(SonosHousehold(id: id, lastKnownIP: ip, name: name))
        }
        knownHouseholds = households
        mirrorLegacyIP()
    }

    // Switches the active household. cachedIP is derived from knownHouseholds so
    // no separate IP write is needed — the next getFirstIP(useCache:) call will
    // race all of the household's known IPs against fresh Bonjour discovery.
    @MainActor
    func switchToHousehold(id: String) {
        guard knownHouseholds.contains(where: { $0.id == id }) else { return }
        preferredHouseHold = id
        mirrorLegacyIP()
    }

    // Adopts a household as preferred and records the responding IP. Called when a
    // known-household IP wins the getGroups race, switching networks without Bonjour.
    // A blocked (user-removed) household is never adopted.
    @MainActor
    func adoptHousehold(id: String, ip: String) {
        guard !isBlocked(id) else { return }
        preferredHouseHold = id
        recordHousehold(id: id, ip: ip)
    }

    // Records a household discovered on the network WITHOUT changing the active
    // selection. Used by the Households screen's scan to surface newly-found homes
    // (e.g. a friend's system you haven't switched to yet).
    @MainActor
    func recordDiscoveredHousehold(id: String, ip: String) {
        recordHousehold(id: id, ip: ip)
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
        if useCache {
            // Primary: derive from the active household (single source of truth).
            if !cachedIP.isEmpty { return cachedIP }
            // Migration: first launch after upgrading from a version that stored
            // only the raw IP without the household model.
            if !sonosStorageIP.legacyIP.isEmpty { return sonosStorageIP.legacyIP }
        }

        // Skip discovery on cellular - Sonos devices are only reachable on local network
        if isCellular {
            throw SonosServiceError.sonosSystemNotFound
        }

        let acquiredBrowse = await acquireExclusiveBrowse()
        // Cancelled while waiting for the gate (e.g. a known-IP task already won the
        // getGroups race): don't start a browse or flip the discovery state.
        guard acquiredBrowse else { throw CancellationError() }
        defer {
            isSearching = false
            stopBrowsing()
            releaseExclusiveBrowse()
        }
        isSearching = true

        return try await performDiscovery()
    }

    /// Performs the actual device discovery.
    @MainActor
    private func performDiscovery() async throws -> String {
        startBrowseAll()

        return try await withThrowingTaskGroup(of: (String, String).self, returning: String.self) { taskGroup in
            var processedIPs = Set<String>()
            // Best IP+ID for the preferred household, and for any household (widening fallback).
            var preferredFallback: (ip: String, id: String)?
            var anyFallback: (ip: String, id: String)?
            let startTime = Date.now
            let maxDiscoveryTime: TimeInterval = 10

            try? await Task.sleep(for: .milliseconds(100))

            while true {
                if Task.isCancelled { break }
                if Date.now > startTime.addingTimeInterval(maxDiscoveryTime) { break }

                if permissionsDenied {
                    taskGroup.cancelAll()
                    throw SonosServiceError.permissionDenied
                }

                let currentIPs = lock.withLock { allIPs }
                let newIPs = currentIPs.subtracting(processedIPs)
                for ip in newIPs {
                    processedIPs.insert(ip)
                    let ipCopy = ip
                    taskGroup.addTask { [weak self] in
                        guard let self else { return ("", "") }
                        let id = await self.getHouseholdIDWithCache(for: ipCopy)
                        return (ipCopy, id)
                    }
                }

                if let result = try? await taskGroup.next() {
                    let (resultIP, householdID) = result
                    guard !resultIP.isEmpty, !householdID.isEmpty else { continue }
                    // A household the user removed must not auto-reconnect.
                    if isBlocked(householdID) { continue }

                    // Keep a widening fallback in case the preferred household is never found.
                    if anyFallback == nil { anyFallback = (resultIP, householdID) }

                    if let preferred = preferredHouseHold {
                        if householdID == preferred {
                            logger.trace("Found preferred household: \(householdID) at IP: \(resultIP)")
                            recordHousehold(id: householdID, ip: resultIP)
                            taskGroup.cancelAll()
                            return resultIP
                        }
                        if preferredFallback == nil { preferredFallback = (resultIP, householdID) }
                    } else {
                        // No preference set — adopt the first device found.
                        logger.trace("No preferred household, using first found: \(householdID) at IP: \(resultIP)")
                        preferredHouseHold = householdID
                        recordHousehold(id: householdID, ip: resultIP)
                        taskGroup.cancelAll()
                        return resultIP
                    }
                }

                let totalConnections = lock.withLock { connections.count }
                if processedIPs.count >= totalConnections && processedIPs.count > 0,
                   Date.now > startTime.addingTimeInterval(0.5) {
                    break
                }

                try? await Task.sleep(for: .milliseconds(25))
            }

            // Drain remaining results.
            while !Task.isCancelled, let (resultIP, householdID) = try? await taskGroup.next() {
                guard !resultIP.isEmpty, !householdID.isEmpty else { continue }
                if isBlocked(householdID) { continue }
                if anyFallback == nil { anyFallback = (resultIP, householdID) }
                if let preferred = preferredHouseHold, householdID == preferred {
                    preferredFallback = (resultIP, householdID)
                    break
                }
            }

            taskGroup.cancelAll()

            // If this discovery was cancelled — e.g. it ran as the Bonjour arm of
            // the getGroups race and a known-IP task already won — do NOT apply the
            // terminal fallbacks. They mutate preferredHouseHold, which would
            // clobber the selection the winner just made (or the one switchHousehold
            // set). The caller's result is discarded on cancellation anyway.
            if Task.isCancelled { throw CancellationError() }

            // Use the preferred household's IP if we found it.
            if let (ip, id) = preferredFallback {
                logger.trace("Returning preferred-household fallback IP: \(ip)")
                recordHousehold(id: id, ip: ip)
                return ip
            }

            // Widening fallback: the preferred household wasn't on this network
            // (e.g. stale preference after a factory reset). Connect to whatever
            // Sonos system is available and update the preference so future
            // launches are fast again.
            if let (ip, id) = anyFallback {
                logger.trace("Preferred household not found; widening to \(id) at \(ip)")
                preferredHouseHold = id
                recordHousehold(id: id, ip: ip)
                return ip
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

        let acquiredBrowse = await acquireExclusiveBrowse()
        guard acquiredBrowse else { return [] }
        startBrowseAll()

        defer {
            stopBrowsing()
            releaseExclusiveBrowse()
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
