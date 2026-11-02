import XCTest
@testable import SubscriptionKit

final class SubscriptionTests: XCTestCase {
    private let periodEnd = Date().addingTimeInterval(30 * 24 * 60 * 60)

    private func info(
        product: String,
        willRenew: Bool,
        expiration: Date?,
        unsubscribed: Date? = nil,
        billingIssue: Date? = nil
    ) -> SubscriptionInfo {
        SubscriptionInfo(
            productIdentifier: product,
            isTrial: false,
            willRenew: willRenew,
            expirationDate: expiration,
            unsubscribeDetectedAt: unsubscribed,
            billingIssueDetectedAt: billingIssue
        )
    }

    func testNotSubscribedHasNoDate() {
        XCTAssertNil(Subscription.notActive.activeUntil)
    }

    func testLifetimeNeverEnds() {
        let lifetime = Subscription(
            isActive: true,
            info: info(product: "com.super.cue.lifetime", willRenew: false, expiration: nil)
        )
        XCTAssertEqual(lifetime.activeUntil, .distantFuture)
    }

    /// Lifetime bought alongside a subscription: RevenueCat's entitlement is
    /// Lifetime's, while `expiration` is the subscription's.
    func testLifetimeWinsOverASubscriptionBoughtAlongside() {
        let both = Subscription(
            isActive: true,
            expiration: periodEnd,
            info: info(product: "com.super.cue.lifetime", willRenew: false, expiration: nil)
        )
        XCTAssertNil(both.periodEnd)
        XCTAssertEqual(both.activeUntil, .distantFuture)
    }

    /// Never locked out for Cue not having run since a renewal.
    func testRenewingHoldsUntilToldOtherwise() {
        let renewing = Subscription(
            isActive: true,
            expiration: periodEnd,
            info: info(product: "com.super.cue.monthly", willRenew: true, expiration: periodEnd)
        )
        XCTAssertEqual(renewing.activeUntil, .distantFuture)
    }

    func testCancelledEndsWithItsPeriod() {
        let cancelled = Subscription(
            isActive: true,
            expiration: periodEnd,
            info: info(product: "com.super.cue.monthly", willRenew: false, expiration: periodEnd)
        )
        XCTAssertEqual(cancelled.activeUntil, periodEnd)
    }

    /// RevenueCat turns `willRenew` off for a failed payment too, but Apple
    /// keeps retrying and a fixed card renews it without Cue running.
    func testBillingProblemStillRenews() {
        let retrying = Subscription(
            isActive: true,
            expiration: periodEnd,
            info: info(product: "com.super.cue.annual", willRenew: false, expiration: periodEnd, billingIssue: Date())
        )
        XCTAssertEqual(retrying.activeUntil, .distantFuture)
    }

    func testCancelledDuringBillingProblemEnds() {
        let cancelled = Subscription(
            isActive: true,
            expiration: periodEnd,
            info: info(product: "com.super.cue.annual", willRenew: false, expiration: periodEnd,
                       unsubscribed: Date(), billingIssue: Date())
        )
        XCTAssertEqual(cancelled.activeUntil, periodEnd)
    }

    /// TestFlight and Debug builds: Super with nothing else known.
    func testBuildGrantNeverEnds() {
        XCTAssertEqual(Subscription(isActive: true).activeUntil, .distantFuture)
        XCTAssertEqual(Subscription.active.activeUntil, .distantFuture)
    }

    func testResumeStartsOnlyFromAnAnswerThatStillHolds() {
        let service = SubscriptionService()

        service.resume(activeUntil: nil)
        XCTAssertFalse(service.subscription.isActive)

        service.resume(activeUntil: .distantPast)
        XCTAssertFalse(service.subscription.isActive)

        service.resume(activeUntil: Date().addingTimeInterval(-60))
        XCTAssertFalse(service.subscription.isActive)

        service.resume(activeUntil: .distantFuture)
        XCTAssertTrue(service.subscription.isActive)
    }
}
