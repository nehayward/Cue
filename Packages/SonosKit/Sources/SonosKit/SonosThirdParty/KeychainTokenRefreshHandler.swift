//
//  KeychainTokenRefreshHandler.swift
//  SonosKit
//
//  Created by Nick Hayward on 6/16/25.
//
import MusicSearchKit
import Foundation
import os

/// The household's music-service accounts (token/key per service), as the
/// speakers hand them over in ZoneGroupState and as Clic's own SMAPI token
/// refreshes rotate them. Kept in the keychain, with each household's list
/// held in memory so a request doesn't read and decode the keychain.
final class KeychainTokenRefreshHandler: TokenRefreshHandler, Sendable {
    static let shared = KeychainTokenRefreshHandler()

    /// Each household's accounts as last read from the keychain or handed
    /// over by the speakers. Guarded by an unfair lock, never held across an
    /// await.
    private let servers = OSAllocatedUnfairLock(initialState: [String: [MediaServer]]())
    private nonisolated(unsafe) let defaultGroup = UserDefaults(suiteName: "group.dance.cue")

    /// Empty values are ignored: the speaker reads behind these return "" or
    /// nil when they fail (common right after the app resumes), and saving that
    /// left every keychain-backed service (SoundCloud, Deezer, Pandora,
    /// SiriusXM…) signed out until the next relaunch.
    var deviceId: String? {
        get {
            defaultGroup?.string(forKey: "deviceID")
        }
        set {
            guard let newValue, !newValue.isEmpty else { return }
            defaultGroup?.set(newValue, forKey: "deviceID")
        }
    }

    /// The household whose service accounts are read. Falls back to the
    /// household the speakers last sent accounts for (see
    /// `mediaServersSaved(householdId:servers:)`) if none has been read yet.
    var householdId: String? {
        get {
            if let stored = defaultGroup?.string(forKey: "householdId"), !stored.isEmpty {
                return stored
            }
            return defaultGroup?.string(forKey: Self.lastMediaServerHouseholdKey)
        }
        set {
            guard let newValue, !newValue.isEmpty else { return }
            defaultGroup?.set(newValue, forKey: "householdId")
        }
    }

    private static let lastMediaServerHouseholdKey = "lastMediaServerHouseholdId"

    /// Called when the speakers hand over a household's service accounts,
    /// after they're saved to the keychain.
    func mediaServersSaved(householdId: String, servers newServers: [MediaServer]) {
        guard !householdId.isEmpty else { return }
        defaultGroup?.set(householdId, forKey: Self.lastMediaServerHouseholdKey)
        servers.withLock { $0[householdId] = newServers }
    }

    // Note: primaryServer key format should be "serverType.rawValue + preferredHouseHoldName"
    // Example: "Spotify + MyHousehold" or "Apple Music + Home"
    var primaryServer: [String: String]? {
        get {
            MemoryFileCache.shared.load(forKey: "primaryServer", as: [String: String].self) ?? [:]
        }
        set {
            MemoryFileCache.shared.save(newValue, forKey: "primaryServer")
        }
    }

    func getKey(for type: SonosServiceType) -> String? {
        guard let householdId else { return nil }
        return "\(type.rawValue).\(householdId)"
    }

    // MARK: Accounts

    /// `householdId`'s accounts, from memory or else the keychain.
    private func mediaServers(householdId: String) -> [MediaServer]? {
        if let cached = servers.withLock({ $0[householdId] }) { return cached }
        guard let stored = KeychainManager.shared.getMediaServers(householdId: householdId) else { return nil }
        servers.withLock { $0[householdId] = stored }
        return stored
    }

    /// The account used for `serviceType`: the one picked as primary when
    /// there are several, otherwise (or if the pick is gone) the first.
    private func server(for serviceType: SonosServiceType, in servers: [MediaServer]) -> MediaServer? {
        let candidates = servers.filter { $0.type == serviceType }
        if candidates.count > 1,
           let primaryKey = getKey(for: serviceType),
           let primaryUDN = primaryServer?[primaryKey],
           let primary = candidates.first(where: { $0.id == primaryUDN }) {
            return primary
        }
        return candidates.first
    }

    // MARK: TokenRefreshHandler

    func handleTokenRefresh(householdId: String, token: String, key: String) async throws {
        try await handleTokenRefresh(serviceType: .spotify, householdId: householdId, token: token, key: key)
    }

    /// Persists a rotated SMAPI token/key pair for `serviceType`'s stored
    /// media server, so later launches read the fresh pair instead of
    /// re-refreshing an already-rotated token.
    func handleTokenRefresh(serviceType: SonosServiceType, householdId: String, token: String, key: String) async throws {
        self.householdId = householdId
        guard var stored = mediaServers(householdId: householdId),
              let target = server(for: serviceType, in: stored),
              let index = stored.firstIndex(where: { $0.id == target.id }) else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }

        stored[index] = MediaServer(
            udn: target.id,
            nickname: target.name,
            token: token,
            key: key,
            serialNum: target.serialNumber,
            flags: target.flags,
            tier: target.tier
        )

        KeychainManager.shared.saveMediaServers(householdId: householdId, servers: stored)
        servers.withLock { [stored] in $0[householdId] = stored }
    }

    func getCredentials() async throws -> Credentials? {
        credentials(for: .spotify)
    }

    /// `service` is a `SonosServiceType` raw value, e.g. "SoundCloud".
    func getCredentials(for service: String) async throws -> Credentials? {
        Self.serviceType(named: service).flatMap(credentials(for:))
    }

    func getCredentials(for serviceType: SonosServiceType) async throws -> Credentials? {
        credentials(for: serviceType)
    }

    func invalidateCredentials(for service: String) {
        invalidateCache()
    }

    private func credentials(for serviceType: SonosServiceType) -> Credentials? {
        guard let deviceId, let householdId,
              let servers = mediaServers(householdId: householdId),
              let server = server(for: serviceType, in: servers) else {
            return nil
        }
        return Credentials(deviceId: deviceId, householdId: householdId, token: server.token, key: server.key)
    }

    private static func serviceType(named name: String) -> SonosServiceType? {
        SonosServiceType.allCases.first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The UDN of the media server backing `serviceType`'s credentials — the
    /// same account `getCredentials(for:)` reads its token from.
    ///
    /// The UDN *is* the service-account cdudn
    /// (`SA_RINCON60423_X_#Svc60423-62fe75eb-Token`), and its middle segment is
    /// the account serial that some services require in the SMAPI householdId.
    func serverUDN(for serviceType: SonosServiceType) -> String? {
        guard let householdId, let servers = mediaServers(householdId: householdId) else { return nil }
        return server(for: serviceType, in: servers)?.id
    }

    /// The account serial from a Sonos service UDN — the middle segment of
    /// `SA_RINCON<sid>_X_#Svc<sid>-<serial>-Token`.
    static func accountSerial(fromUDN udn: String) -> String? {
        let parts = udn.components(separatedBy: "-")
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    func getAccessToken(for serviceType: SonosServiceType) async throws -> String? {
        credentials(for: serviceType)?.token
    }

    /// Drops the in-memory accounts so the next request reads the keychain.
    func invalidateCache() {
        servers.withLock { $0.removeAll() }
    }
}
