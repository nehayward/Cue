import OSLog
import RevenueCat
import SwiftUI

/// The paywall's footer: the plans, Purchase, the renewal terms, Restore
/// Purchases and the legal links. Cue's own, not RevenueCat's: its footer
/// mode needs one of RevenueCat's older template paywalls set up on the
/// offering, and without one it drew RevenueCat's default paywall over the
/// table. Until the offering is in, a spinner; when it couldn't load, why and
/// Try Again.
struct PurchaseFooter: View {
    let offering: Offering?
    let failed: Bool
    let retry: () -> Void
    let purchased: () -> Void

    @State private var selected: Package?
    /// Packages whose free trial this Apple Account can still take.
    @State private var trialEligible: Set<String> = []
    @State private var isBusy = false
    @State private var message: String?

    private static let log = Logger(subsystem: "dance.cue", category: "paywall")

    var body: some View {
        VStack(spacing: 12) {
            if let offering, !plans(in: offering).isEmpty {
                let plans = plans(in: offering)
                let choice = selected ?? plans.first { $0.packageType == .annual } ?? plans[0]

                HStack(spacing: 10) {
                    ForEach(plans, id: \.identifier) { package in
                        PlanCard(
                            package: package,
                            saving: package.packageType == .annual ? Self.saving(in: plans) : nil,
                            isSelected: package.identifier == choice.identifier
                        ) {
                            selected = package
                            message = nil
                        }
                    }
                }
                .disabled(isBusy)

                Button {
                    Task { await purchase(choice) }
                } label: {
                    ZStack {
                        Text(buttonTitle(for: choice))
                            .opacity(isBusy ? 0 : 1)
                        if isBusy {
                            ProgressView()
                                .tint(.black)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.black)
                    .background(Color.accentColor, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Text(message ?? terms(for: choice))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(message == nil ? 0.5 : 0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Button("Restore Purchases") {
                        Task { await restore() }
                    }
                    .disabled(isBusy)
                    Text("·")
                    Link("Terms of Use", destination: URL(string: "https://cue.dance/terms")!)
                    Text("·")
                    Link("Privacy Policy", destination: URL(string: "https://cue.dance/privacy")!)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .tint(.white.opacity(0.6))
                .buttonStyle(.plain)
            } else if failed || offering != nil {
                Text("Cue Super's prices didn't load.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 8)
        // Opaque, so the table scrolls under it rather than showing through.
        .background(Color.black)
        .overlay(alignment: .top) {
            Divider().overlay(Color.white.opacity(0.1))
        }
        .task(id: offering?.identifier) {
            guard let offering else { return }
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: plans(in: offering))
            trialEligible = Set(eligibility.filter { $0.value.status == .eligible }.map(\.key.identifier))
        }
    }

    /// Monthly, yearly and lifetime, in that order, then anything else.
    private func plans(in offering: Offering) -> [Package] {
        let order: [PackageType] = [.monthly, .annual, .lifetime]
        return offering.availablePackages.sorted {
            (order.firstIndex(of: $0.packageType) ?? order.count) < (order.firstIndex(of: $1.packageType) ?? order.count)
        }
    }

    /// What a year costs against twelve months, as a whole percentage.
    private static func saving(in plans: [Package]) -> Int? {
        guard let monthly = plans.first(where: { $0.packageType == .monthly })?.storeProduct.price,
              let annual = plans.first(where: { $0.packageType == .annual })?.storeProduct.price,
              monthly > 0 else { return nil }
        // Through Double: `Int(truncating:)` reads a long Decimal like
        // 37.2236… as 0.
        let ratio = NSDecimalNumber(decimal: annual / (monthly * 12)).doubleValue
        let percent = Int((1 - ratio) * 100)
        return percent > 0 ? percent : nil
    }

    private func trial(of package: Package) -> SubscriptionPeriod? {
        guard trialEligible.contains(package.identifier),
              let discount = package.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial else { return nil }
        return discount.subscriptionPeriod
    }

    private func buttonTitle(for package: Package) -> String {
        if let trial = trial(of: package) {
            return "Try Free for \(trial.length)"
        }
        return package.storeProduct.subscriptionPeriod == nil ? "Buy Once" : "Subscribe"
    }

    /// What App Review asks to be said by the button: the trial, the price,
    /// the period, and that it renews.
    private func terms(for package: Package) -> String {
        let product = package.storeProduct
        guard let period = product.subscriptionPeriod else {
            return "One payment of \(product.localizedPriceString), for good."
        }
        let price = "\(product.localizedPriceString) \(period.every)"
        let start = trial(of: package).map { "Free for \($0.length), then \(price)." } ?? "\(price)."
        return "\(start) Renews until you cancel."
    }

    private func purchase(_ package: Package) async {
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                purchased()
            }
        } catch {
            if (error as? ErrorCode) == .purchaseCancelledError { return }
            Self.log.error("paywall: purchase of \(package.storeProduct.productIdentifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            message = "The purchase didn't go through: \(error.localizedDescription)"
        }
    }

    private func restore() async {
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            // Super arriving closes the paywall (CuePaywall watches the
            // subscription); this only has to say when nothing came back.
            if info.entitlements.active.isEmpty && info.nonSubscriptions.isEmpty {
                message = "There's no Cue Super on this Apple Account to restore."
            }
        } catch {
            Self.log.error("paywall: restore failed: \(error.localizedDescription, privacy: .public)")
            message = "Restoring didn't work: \(error.localizedDescription)"
        }
    }
}

/// One plan: its name, price and period, and the saving on the yearly one.
private struct PlanCard: View {
    let package: Package
    let saving: Int?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                Text(name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.6))
                Text(package.storeProduct.localizedPriceString)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(per)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : .white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .top) {
                if let saving {
                    Text("SAVE \(saving)%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: .capsule)
                        .offset(y: -9)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([name, package.storeProduct.localizedPriceString, per, saving.map { "save \($0) percent" }].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var name: String {
        switch package.packageType {
        case .monthly: "Monthly"
        case .annual: "Yearly"
        case .lifetime: "Lifetime"
        default: package.storeProduct.localizedTitle
        }
    }

    private var per: String {
        package.storeProduct.subscriptionPeriod?.every ?? "once"
    }
}

private extension SubscriptionPeriod {
    /// "a month", "a year"; "every 3 months" for a longer period.
    var every: String {
        value == 1 ? "a \(Self.name(of: unit))" : "every \(length)"
    }

    /// "1 week", "2 weeks", "3 days".
    var length: String {
        "\(value) \(Self.name(of: unit))\(value == 1 ? "" : "s")"
    }

    private static func name(of unit: Unit) -> String {
        switch unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
    }
}
