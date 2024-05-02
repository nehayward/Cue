import Foundation

// TODO: Add to app.
public struct DeviceInfo: Identifiable {
    public let id: String
    public let description: String
    public let model: String
    public let iconURL: URL
    public let displayName: String
}
