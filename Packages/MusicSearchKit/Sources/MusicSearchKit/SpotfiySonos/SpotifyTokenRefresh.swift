import Foundation
import os

public struct Credentials {
    public let deviceId: String
    public let householdId: String
    public let token: String
    public let key: String
    
    public init(deviceId: String, householdId: String, token: String, key: String) {
        self.deviceId = deviceId
        self.householdId = householdId
        self.token = token
        self.key = key
    }
}

public protocol TokenRefreshHandler {
    func handleTokenRefresh(householdId: String, token: String, key: String) async throws
    func getCredentials() async throws -> Credentials?
    func getCredentials(for service: String) async throws -> Credentials?
}

public struct SpotifyTokenRefreshResponse {
    public let authToken: String
    public let privateKey: String
    public let userIdHashCode: String
    public let accountTier: String
    public let nickname: String
}

// Unified token refresh coordinator to prevent race conditions
public final class TokenRefreshCoordinator {
    public static let shared = TokenRefreshCoordinator()
    
    private var refreshInProgress: [String: Bool] = [:]
    private let lock = OSAllocatedUnfairLock()
    
    private init() {}
    
    public func refreshToken(credentials: Credentials) async throws -> (String, String)? {
        let key = "\(credentials.token):\(credentials.key)"
        
        // Check if refresh is already in progress
        let shouldStartRefresh = lock.withLock {
            if refreshInProgress[key] == true {
                return false // Refresh already in progress
            } else {
                refreshInProgress[key] = true
                return true // Start new refresh
            }
        }
        
        if !shouldStartRefresh {
            // Wait for the existing refresh to complete by polling
            while true {
                try await Task.sleep(for: .milliseconds(10)) // 10ms - much faster
                let isStillInProgress = lock.withLock {
                    refreshInProgress[key] == true
                }
                if !isStillInProgress {
                    break
                }
            }
            
            // Try to get fresh credentials after the refresh completed
            return try await SpotifySonosAPI.shared.refreshTokenIfNeeded(credentials: credentials)
        }
        
        // Perform the actual refresh
        do {
            let result = try await SpotifySonosAPI.shared.refreshTokenIfNeeded(credentials: credentials)
            lock.withLock {
                refreshInProgress[key] = false
            }
            return result
        } catch {
            lock.withLock {
                refreshInProgress[key] = false
            }
            throw error
        }
    }
}
