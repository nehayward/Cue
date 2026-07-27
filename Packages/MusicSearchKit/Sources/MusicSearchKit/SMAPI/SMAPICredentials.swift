import Foundation

/// Sonos SMAPI credentials required to call a music service's SMAPI endpoint.
/// Distinct from a bare OAuth token — SMAPI calls always need token + service
/// key + householdId.
///
/// `deviceId` is the controller's device id. Sonos-operated services such as
/// Sonos Radio require it (alongside the loginToken) in the credentials header;
/// other services (e.g. Deezer) omit it.
public struct SMAPICredentials: Sendable {
    public let token: String
    public let key: String
    public let householdId: String
    public let deviceId: String?

    public init(token: String, key: String, householdId: String, deviceId: String? = nil) {
        self.token = token
        self.key = key
        self.householdId = householdId
        self.deviceId = deviceId
    }
}
