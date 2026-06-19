import Foundation

/// Sonos SMAPI credentials required to call a music service's SMAPI endpoint.
/// Distinct from a bare OAuth token — SMAPI calls always need token + service key + householdId.
public struct SMAPICredentials: Sendable {
    public let token: String
    public let key: String
    public let householdId: String

    public init(token: String, key: String, householdId: String) {
        self.token = token
        self.key = key
        self.householdId = householdId
    }
}
