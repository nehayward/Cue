import Foundation

public struct VanishedDevice: Identifiable {
    public let id: String
    public let name: String?
    public let reason: String?
    public let IP: String?
    public let lastSeen: Date?
    public let info: String?
    public let macAddress: String?
}
