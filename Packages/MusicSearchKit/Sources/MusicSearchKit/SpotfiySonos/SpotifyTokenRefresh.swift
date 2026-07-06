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

    private typealias RefreshTask = Task<(String, String), Error>
    private var refreshTasks: [String: RefreshTask] = [:]
    private let lock = OSAllocatedUnfairLock()

    private init() {}

    /// Refreshes the SMAPI token for the household in `credentials`, persisting
    /// the result through `handler` before any caller resumes.
    ///
    /// Concurrent callers for the same household share one in-flight refresh —
    /// a second network refresh would invalidate the token the first one just
    /// obtained. Keying on the household (not the stale token pair) also
    /// coalesces callers that hold different stale token generations.
    public func refreshToken(credentials: Credentials, handler: TokenRefreshHandler? = nil) async throws -> (String, String) {
        let key = credentials.householdId

        let task = lock.withLock { () -> RefreshTask in
            if let existing = refreshTasks[key] {
                return existing
            }
            let task = RefreshTask {
                // Removed only after the refreshed token has been persisted, so
                // a caller that misses the join window reads fresh credentials
                // from the handler instead of re-refreshing with dead ones.
                defer {
                    self.lock.withLock { _ = self.refreshTasks.removeValue(forKey: key) }
                }
                let (token, tokenKey) = try await SpotifySonosAPI.shared.refreshTokenIfNeeded(credentials: credentials)
                if token != credentials.token || tokenKey != credentials.key {
                    try await handler?.handleTokenRefresh(householdId: credentials.householdId, token: token, key: tokenKey)
                }
                return (token, tokenKey)
            }
            refreshTasks[key] = task
            return task
        }

        return try await value(of: task)
    }

    /// Awaits the shared task while staying responsive to cancellation of the
    /// caller. `task.value` alone suspends until the refresh finishes even if
    /// the awaiting task is cancelled; this bridge lets a cancelled caller bail
    /// out immediately while the refresh keeps running for the other waiters.
    private func value(of task: RefreshTask) async throws -> (String, String) {
        typealias Continuation = CheckedContinuation<(String, String), Error>
        let state = OSAllocatedUnfairLock<(continuation: Continuation?, isResumed: Bool)>(initialState: (nil, false))

        let takeContinuation: @Sendable () -> Continuation? = {
            state.withLock { state in
                guard !state.isResumed else { return nil }
                state.isResumed = true
                let continuation = state.continuation
                state.continuation = nil
                return continuation
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: Continuation) in
                let alreadyCancelled = state.withLock { state -> Bool in
                    guard !state.isResumed else { return true }
                    state.continuation = continuation
                    return false
                }
                if alreadyCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                Task {
                    let result: Result<(String, String), Error>
                    do {
                        result = .success(try await task.value)
                    } catch {
                        result = .failure(error)
                    }
                    takeContinuation()?.resume(with: result)
                }
            }
        } onCancel: {
            takeContinuation()?.resume(throwing: CancellationError())
        }
    }
}
