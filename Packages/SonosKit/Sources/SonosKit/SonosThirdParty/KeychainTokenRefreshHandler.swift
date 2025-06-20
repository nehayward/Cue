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
    
    // Cache for credentials to avoid repeated keychain access
    private var cachedCredentials: Credentials?
    
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
    
    func handleTokenRefresh(householdId: String, token: String, key: String) async throws {
        self.householdId = householdId
        guard var servers = KeychainManager.shared.getMediaServers(householdId: householdId),
              let index = servers.firstIndex(where: { $0.type == .spotify }) else {
            throw SpotifyMetadataError.tokenRefreshFailed
        }
        
        let updatedServer = servers[index]
        servers[index] = MediaServer(
            udn: updatedServer.id,
            nickname: updatedServer.name,
            token: token,
            key: key,
            serialNum: updatedServer.serialNumber,
            flags: updatedServer.flags,
            tier: updatedServer.tier
        )
        
        KeychainManager.shared.saveMediaServers(householdId: householdId, servers: servers)
        
        // Invalidate cache when token is refreshed
        invalidateCache()
    }
    
    func getCredentials() async throws -> Credentials? {
        if let cachedCredentials  {
            return cachedCredentials
        }
        guard let deviceId, let householdId else {
            return nil
        }
        
        guard let servers = KeychainManager.shared.getMediaServers(householdId: householdId),
              let spotifyServer = servers.first(where: { $0.type == .spotify }) else {
            return nil
        }
        
        let credentials = Credentials(
            deviceId: deviceId,
            householdId: householdId,
            token: spotifyServer.token,
            key: spotifyServer.key
        )
        
        // Cache the credentials
        cachedCredentials = credentials
        return credentials
    }
    
    private func invalidateCache() {
        cachedCredentials = nil
    }
}
