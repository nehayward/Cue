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

    private var refreshTasks: [String: Task<(String, String)?, Error>] = [:]
    private let lock = OSAllocatedUnfairLock()

    private init() {}

    public func refreshToken(credentials: Credentials) async throws -> (String, String)? {
        let key = "\(credentials.token):\(credentials.key)"

        // Concurrent callers holding the same stale credentials share a single
        // in-flight refresh; a second network refresh here would invalidate the
        // token the first one just obtained.
        let task = lock.withLock { () -> Task<(String, String)?, Error> in
            if let existing = refreshTasks[key] {
                return existing
            }
            let task = Task { [weak self] () throws -> (String, String)? in
                defer {
                    self?.lock.withLock { _ = self?.refreshTasks.removeValue(forKey: key) }
                }
                return try await SpotifySonosAPI.shared.refreshTokenIfNeeded(credentials: credentials)
            }
            refreshTasks[key] = task
            return task
        }

        return try await task.value
    }
}
