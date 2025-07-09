//
//  KeychainTokenRefreshHandler.swift
//  SonosKit
//
//  Created by Nick Hayward on 6/16/25.
//
import MusicSearchKit
import Foundation

final class KeychainTokenRefreshHandler: TokenRefreshHandler {
    static var shared = KeychainTokenRefreshHandler()
    
    fileprivate var cache = MemoryFileCache.shared
    // Cache for credentials to avoid repeated keychain access
    private var cachedCredentials: [SonosServiceType: Credentials] = [:]
    private let credentialsQueue = DispatchQueue(label: "com.clic.credentials", attributes: .concurrent)
    
    var deviceId: String? {
        get {
            UserDefaults.standard.string(forKey: "deviceID")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "deviceID")
        }
    }
    
    var householdId: String? {
        get {
            UserDefaults.standard.string(forKey: "householdId")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "householdId")
        }
    }
    
    // Note: primaryServer key format should be "serverType.rawValue + preferredHouseHoldName"
    // Example: "Spotify + MyHousehold" or "Apple Music + Home"
    var primaryServer: [String: String]? {
        get {
            cache.load(forKey: "primaryServer", as: [String: String].self) ?? [:]
        }
        set {
            cache.save(newValue, forKey: "primaryServer")
        }
    }
    
    func getKey(for type: SonosServiceType) -> String? {
        guard let householdId else { return nil }
        return "\(type.rawValue).\(householdId)"
    }
    
    func handleTokenRefresh(householdId: String, token: String, key: String) async throws {
        self.householdId = householdId
        guard var servers = KeychainManager.shared.getMediaServers(householdId: householdId) else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let spotifyServers = servers.filter { $0.type == .spotify }
        let targetServer: MediaServer?
        
        // Use primaryServer if more than 2 Spotify servers exist
        if spotifyServers.count > 1, let primaryServer = primaryServer, let primaryKey = getKey(for: .spotify) {
            if let primaryUDN = primaryServer[primaryKey] {
                targetServer = servers.first(where: { $0.id == primaryUDN && $0.type == .spotify })
            } else {
                targetServer = spotifyServers.first
            }
        } else {
            targetServer = spotifyServers.first
        }
        
        guard let targetServer = targetServer,
              let index = servers.firstIndex(where: { $0.id == targetServer.id }) else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        servers[index] = MediaServer(
            udn: targetServer.id,
            nickname: targetServer.name,
            token: token,
            key: key,
            serialNum: targetServer.serialNumber,
            flags: targetServer.flags,
            tier: targetServer.tier
        )
        
        KeychainManager.shared.saveMediaServers(householdId: householdId, servers: servers)
        invalidateCache()
    }
    
    func getCredentials() async throws -> Credentials? {
        return try await getCredentials(for: .spotify)
    }
    
    func getCredentials(for service: String) async throws -> Credentials? {
        // MARK: Fix for remaining services
        return try await getCredentials(for: .soundcloud)
    }
    
    func getCredentials(for serviceType: SonosServiceType) async throws -> Credentials? {
        if let cachedCredentials = credentialsQueue.sync(execute: { cachedCredentials[serviceType] }) {
            return cachedCredentials
        }
        
        guard let deviceId, let householdId else {
            return nil
        }
        
        guard let servers = KeychainManager.shared.getMediaServers(householdId: householdId) else {
            return nil
        }
        
        let serviceServers = servers.filter { $0.type == serviceType }
        let targetServer: MediaServer?
        
        // Use primaryServer if more than 2 servers of this type exist
        if serviceServers.count > 1, let primaryServer = primaryServer, let primaryKey = getKey(for: serviceType) {
            if let primaryUDN = primaryServer[primaryKey] {
                targetServer = servers.first(where: { $0.id == primaryUDN && $0.type == serviceType })
            } else {
                targetServer = serviceServers.first
            }
        } else {
            targetServer = serviceServers.first
        }
        
        guard let targetServer = targetServer else {
            return nil
        }
        
        let credentials = Credentials(
            deviceId: deviceId,
            householdId: householdId,
            token: targetServer.token,
            key: targetServer.key
        )
        
        credentialsQueue.async(flags: .barrier) { [weak self] in
            self?.cachedCredentials[serviceType] = credentials
        }
        return credentials
    }
    
    func getAccessToken(for serviceType: SonosServiceType) async throws -> String? {
        guard let credentials = try await getCredentials(for: serviceType) else {
            return nil
        }
        return credentials.token
    }
    
    func invalidateCache() {
        credentialsQueue.async(flags: .barrier) { [weak self] in
            self?.cachedCredentials.removeAll()
        }
    }
    
    func invalidateCache(for serviceType: SonosServiceType) {
        credentialsQueue.async(flags: .barrier) { [weak self] in
            self?.cachedCredentials.removeValue(forKey: serviceType)
        }
    }
    
    public func setCredentials(for server: MediaServer) {
        guard let deviceId = deviceId, let householdId else {
            invalidateCache()
            return
        }
        let credentials = Credentials(
            deviceId: deviceId,
            householdId: householdId,
            token: server.token,
            key: server.key
        )
        credentialsQueue.async(flags: .barrier) { [weak self] in
            self?.cachedCredentials[server.type] = credentials
        }
    }
}
