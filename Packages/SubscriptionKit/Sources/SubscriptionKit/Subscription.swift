import Foundation
import RevenueCat

public class Subscription: Codable, Equatable {
    public var isActive: Bool
    public var expiration: Date?
    public var info: SubscriptionInfo?

    public init(isActive: Bool, expiration: Date? = nil, info: SubscriptionInfo? = nil) {
        self.isActive = isActive
        self.expiration = expiration
        self.info = info
    }

    public static func == (lhs: Subscription, rhs: Subscription) -> Bool {
        lhs.isActive == rhs.isActive &&
        lhs.expiration == rhs.expiration
    }
}

extension Subscription {
    public static var notActive = Subscription(isActive: false)
}


// Enum of supported stores
public enum Store: Int, Codable, CaseIterable {
    case appStore = 0
    case macAppStore = 1
    case playStore = 2
    case stripe = 3
    case promotional = 4
    case unknownStore = 5
    case amazon = 6
}

// Enum of supported period types for an entitlement
public enum PeriodType: Int, Codable, CaseIterable {
    case normal = 0
    case intro = 1
    case trial = 2
}

// The EntitlementInfo struct gives you access to all of the information about the status of a user entitlement
public struct SubscriptionInfo: Codable {
    public let identifier: String
    public let isActive: Bool
    public let willRenew: Bool
    public let periodType: PeriodType
    public let latestPurchaseDate: Date?
    public let originalPurchaseDate: Date?
    public let expirationDate: Date?
    public let store: Store
    public let productIdentifier: String
    public let productPlanIdentifier: String?
    public let isSandbox: Bool
    public let unsubscribeDetectedAt: Date?
    public let billingIssueDetectedAt: Date?
    public let ownershipType: PurchaseOwnershipType
    public let verification: VerificationResult

    public enum PurchaseOwnershipType: Int, Codable {
        case purchased
        case familyShared
        case unknown
    }

    public enum VerificationResult: Int, Codable {
        case verified
        case unverified
        case unknown
    }
}

extension EntitlementInfo {
    var toSubscriptionInfo: SubscriptionInfo {
        SubscriptionInfo(
            identifier: identifier,
            isActive: isActive,
            willRenew: willRenew,
            periodType: PeriodType(rawValue: periodType.rawValue) ?? .normal,
            latestPurchaseDate: latestPurchaseDate,
            originalPurchaseDate: originalPurchaseDate,
            expirationDate: expirationDate,
            store: Store(rawValue: store.rawValue) ?? .unknownStore,
            productIdentifier: productIdentifier,
            productPlanIdentifier: productPlanIdentifier,
            isSandbox: isSandbox,
            unsubscribeDetectedAt: unsubscribeDetectedAt,
            billingIssueDetectedAt: billingIssueDetectedAt,
            ownershipType: SubscriptionInfo.PurchaseOwnershipType(rawValue: ownershipType.rawValue) ?? .unknown,
            verification: SubscriptionInfo.VerificationResult(rawValue: verification.rawValue) ?? .unknown
        )
    }
}
