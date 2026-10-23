import Foundation
import os

/// One SMAPI service's login for this session: the household's stored
/// token/key until the service rejects it, then whatever `refreshAuthToken`
/// handed back. Shared by `SMAPIServiceClient` (Pandora, SiriusXM) and
/// `SonosRadioAPI`, which differ only in how they ask for a new token.
///
/// The state is guarded by an unfair lock — never held across an await — so
/// concurrent requests that both hit an expired token share one in-flight
/// exchange instead of firing duplicate (mutually invalidating) ones.
final class SMAPILoginSession: Sendable {
    typealias Login = (token: String, key: String)

    private struct State {
        /// A pair returned by a refresh this session, substituted into every
        /// later request.
        var refreshedLogin: Login?
        /// The in-flight refresh, joined by concurrent auth failures.
        var refreshTask: Task<Login?, Never>?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Called after a successful refresh so the owner can persist the rotated
    /// pair (the stored household token is stale once rotated).
    private let onTokenRefreshed: (@Sendable (_ token: String, _ key: String) -> Void)?

    init(onTokenRefreshed: (@Sendable (_ token: String, _ key: String) -> Void)?) {
        self.onTokenRefreshed = onTokenRefreshed
    }

    /// `credentials` with this session's refreshed token substituted, if any.
    func effectiveCredentials(_ credentials: SMAPICredentials) -> SMAPICredentials {
        guard let refreshed = state.withLock({ $0.refreshedLogin }) else { return credentials }
        return SMAPICredentials(
            token: refreshed.token,
            key: refreshed.key,
            householdId: credentials.householdId,
            deviceId: credentials.deviceId
        )
    }

    /// Refreshes the login after a request using `failedToken` was rejected.
    /// If another request already rotated past that token there's nothing to
    /// do, and a refresh already in flight is joined. `exchange` asks the
    /// service for a new pair given the current credentials. Returns whether
    /// a valid login is now available.
    func refresh(
        afterFailureOf failedToken: String,
        credentials: SMAPICredentials,
        exchange: @escaping @Sendable (SMAPICredentials) async -> Login?
    ) async -> Bool {
        let current = effectiveCredentials(credentials)

        let (task, startedHere): (Task<Login?, Never>?, Bool) = state.withLock { state in
            if (state.refreshedLogin?.token ?? credentials.token) != failedToken {
                return (nil, false)
            }
            if let existing = state.refreshTask {
                return (existing, false)
            }
            let started = Task { await exchange(current) }
            state.refreshTask = started
            return (started, true)
        }
        guard let task else { return true }

        let refreshed = await task.value

        state.withLock { state in
            state.refreshTask = nil
            // A failed refresh means the session token is dead too; keeping it
            // made every later request fail with it until relaunch. Go back to
            // the stored household token, which the speakers keep current.
            state.refreshedLogin = refreshed
        }

        guard let refreshed else { return false }
        if startedHere {
            onTokenRefreshed?(refreshed.token, refreshed.key)
        }
        return true
    }
}
