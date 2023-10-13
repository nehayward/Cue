import Foundation

public class Subscription: Codable, Equatable {
    public var isActive: Bool
    public var expiration: Date?

    public init(isActive: Bool, expiration: Date? = nil) {
        self.isActive = isActive
        self.expiration = expiration
    }

    public static func == (lhs: Subscription, rhs: Subscription) -> Bool {
        lhs.isActive == rhs.isActive &&
        lhs.expiration == rhs.expiration
    }
}

extension Subscription {
    public static var notActive = Subscription(isActive: false)
}

