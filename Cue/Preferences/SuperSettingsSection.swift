import SubscriptionKit
import SwiftUI

/// Cue Super at the top of Settings: the paywall's banner without it, else
/// the plan and when it renews, opening the paywall. On the iPhone's
/// Settings and the Mac's General pane (`GeneralSettingsScreen`), each with
/// a router whose full-screen cover shows the paywall.
struct SuperSettingsSection: View {
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(FeatureGate.self) private var featureGate
    @Environment(Router.self) private var router

    var body: some View {
        Section {
            if !featureGate.hasSuper {
                PaywallButtonView()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router.presentedFullScreenCover = .paywall
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Cue Super")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor.gradient)
                            }
                            subscriptionStatusLine
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }
        } header: {
            Spacer(minLength: 0).listRowInsets(EdgeInsets())
        }
        .task {
            await subscriptionService.checkSubscription()
        }
    }

    private var subscriptionStatusLine: Text {
        let info = subscriptionService.subscription.info
        var plan = info.flatMap { planName(for: $0.productIdentifier) }

        if plan == "Lifetime" {
            return Text("Lifetime")
        }
        // "Annual Free Trial · Renews …": the renewal is the first payment.
        if info?.isTrial == true {
            plan = [plan, "Free Trial"].compactMap { $0 }.joined(separator: " ")
        }
        if let info, let expiration = info.expirationDate {
            let dateText = Text(expiration, style: .date)
            let verb = info.willRenew ? "Renews" : "Expires"
            if let plan {
                return Text("\(plan) · \(verb) \(dateText)")
            }
            return Text("\(verb) \(dateText)")
        }
        if let plan {
            return Text(plan)
        }
        return Text("Active subscription")
    }

    private func planName(for productIdentifier: String) -> String? {
        let id = productIdentifier.lowercased()
        if id.contains("lifetime") { return "Lifetime" }
        if id.contains("annual") || id.contains("yearly") { return "Annual" }
        if id.contains("month") { return "Monthly" }
        return nil
    }
}

/// Contact Support's mail to hi@cue.dance, carrying the version and this
/// install's ID: Settings' row, and Help ▸ Contact Support on the Mac.
enum SupportMail {
    @MainActor static var url: URL {
        let body = "\n\nVersion: \(OSEnvironment.versionInfo)\nID: \(SubscriptionService.shared.userID)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "hi@cue.dance"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Support"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url!
    }
}
