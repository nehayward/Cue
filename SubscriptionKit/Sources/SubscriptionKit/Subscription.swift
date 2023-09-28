import Foundation

public struct Subscription: Codable {
    public var isActive: Bool
    public var expiration: Date?

    public init(isActive: Bool, expiration: Date? = nil) {
        self.isActive = isActive
        self.expiration = expiration
    }
}

extension Subscription {
    public static var notActive = Subscription(isActive: false)
}

