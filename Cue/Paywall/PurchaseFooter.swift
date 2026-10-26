import OSLog
import RevenueCat
import SwiftUI

/// The paywall's footer: the plans, Purchase, the renewal terms, Restore
/// Purchases and the legal links. Cue's own, not RevenueCat's: its footer
/// mode needs one of RevenueCat's older template paywalls set up on the
/// offering, and without one it drew RevenueCat's default paywall over the
/// table. Until the offering is in, a spinner; when it couldn't load, why and
/// Try Again.
///
/// A sale needs no app update. An introductory offer set up in App Store
/// Connect (a free trial, a first year at half price, a few months at a lower
/// price) shows on its plan, the button and the terms, to an Apple Account
/// that can still take it. The offering's metadata in RevenueCat can add a
/// badge to one plan and a headline (`Offering.saleBadge`, `saleHeadline`).
struct PurchaseFooter: View {
    let offering: Offering?
    let failed: Bool
    let retry: () -> Void
    let purchased: () -> Void

    @State private var selected: Package?
    /// Packages whose introductory offer this Apple Account can still take.
    @State private var introEligible: Set<String> = []
    @State private var isBusy = false
    @State private var message: String?

    private static let log = Logger(subsystem: "dance.cue", category: "paywall")

    var body: some View {
        VStack(spacing: 12) {
            if let offering, !plans(in: offering).isEmpty {
                let plans = plans(in: offering)
                let choice = selected
                    ?? plans.first { $0.packageType == offering.saleBadgePlan }
                    ?? plans.first { $0.packageType == .annual }
                    ?? plans[0]

                HStack(spacing: 10) {
                    ForEach(plans, id: \.identifier) { package in
                        PlanCard(
                            package: package,
                            intro: paidIntro(of: package),
                            badge: badge(for: package, in: plans, offering: offering),
                            shimmers: offering.saleBadge != nil,
                            isSelected: package.identifier == choice.identifier
                        ) {
                            withAnimation(.spring(duration: 0.35, bounce: 0.35)) {
                                selected = package
                            }
                            message = nil
                        }
                    }
                }
                // Every card as tall as the tallest, struck-through price or not.
                .fixedSize(horizontal: false, vertical: true)
                .disabled(isBusy)
                .sensoryFeedback(.selection, trigger: choice.identifier)

                Button {
                    Task { await purchase(choice) }
                } label: {
                    ZStack {
                        // The wording changes at once; only the button bounces.
                        Text(buttonTitle(for: choice))
                            .transaction(value: choice.identifier) { $0.animation = nil }
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
                // And the button gives a little bounce.
                .keyframeAnimator(initialValue: 1.0, trigger: choice.identifier) { button, scale in
                    button.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.04, duration: 0.12)
                    SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                }

                Text(message ?? terms(for: choice))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(message == nil ? 0.5 : 0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transaction(value: choice.identifier) { $0.animation = nil }

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
            #if DEBUG
            if offering.identifier == PaywallSalePreview.identifier {
                introEligible = Set(offering.availablePackages.map(\.identifier))
                return
            }
            #endif
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: plans(in: offering))
            introEligible = Set(eligibility.filter { $0.value.status == .eligible }.map(\.key.identifier))
        }
    }

    /// Monthly, yearly and lifetime, in that order, then anything else.
    private func plans(in offering: Offering) -> [Package] {
        let order: [PackageType] = [.monthly, .annual, .lifetime]
        return offering.availablePackages.sorted {
            (order.firstIndex(of: $0.packageType) ?? order.count) < (order.firstIndex(of: $1.packageType) ?? order.count)
        }
    }

    /// The offering's own badge on its plan and no other, so a sale has the
    /// paywall to itself; without one, what an introductory price takes off,
    /// else what the yearly plan saves on twelve months.
    private func badge(for package: Package, in plans: [Package], offering: Offering) -> String? {
        if let badge = offering.saleBadge {
            return package.packageType == offering.saleBadgePlan ? badge.uppercased() : nil
        }
        if let intro = paidIntro(of: package), let off = Self.percentOff(intro, from: package.storeProduct) {
            return "\(off)% OFF"
        }
        if package.packageType == .annual, let saving = Self.saving(in: plans) {
            return "SAVE \(saving)%"
        }
        return nil
    }

    /// What a year costs against twelve months, as a whole percentage.
    private static func saving(in plans: [Package]) -> Int? {
        guard let monthly = plans.first(where: { $0.packageType == .monthly })?.storeProduct.price,
              let annual = plans.first(where: { $0.packageType == .annual })?.storeProduct.price,
              monthly > 0 else { return nil }
        return percent(annual, of: monthly * 12)
    }

    /// What an introductory price takes off the regular one, when it's for
    /// the same period (a first year at half price, a month at a lower price).
    private static func percentOff(_ intro: StoreProductDiscount, from product: StoreProduct) -> Int? {
        guard let period = product.subscriptionPeriod,
              intro.subscriptionPeriod.unit == period.unit,
              intro.subscriptionPeriod.value == period.value,
              product.price > 0 else { return nil }
        return percent(intro.price, of: product.price)
    }

    /// How much less `part` is than `whole`, as a whole percentage. Through
    /// Double: `Int(truncating:)` reads a long Decimal like 37.2236… as 0.
    private static func percent(_ part: Decimal, of whole: Decimal) -> Int? {
        let ratio = NSDecimalNumber(decimal: part / whole).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    /// The introductory offer this Apple Account can take on the plan.
    private func intro(of package: Package) -> StoreProductDiscount? {
        guard introEligible.contains(package.identifier) else { return nil }
        return package.storeProduct.introductoryDiscount
    }

    /// The introductory offer, when it's a lower price rather than free.
    private func paidIntro(of package: Package) -> StoreProductDiscount? {
        intro(of: package).flatMap { $0.paymentMode == .freeTrial ? nil : $0 }
    }

    private func buttonTitle(for package: Package) -> String {
        guard let intro = intro(of: package) else {
            return package.storeProduct.subscriptionPeriod == nil ? "Buy Once" : "Subscribe"
        }
        switch intro.paymentMode {
        case .freeTrial:
            return "Try Free for \(intro.subscriptionPeriod.length)"
        case .payUpFront:
            return "Get the \(intro.subscriptionPeriod.first.capitalized) for \(intro.localizedPriceString)"
        case .payAsYouGo:
            return "Start at \(intro.localizedPriceString) \(intro.subscriptionPeriod.every)"
        @unknown default:
            return "Subscribe"
        }
    }

    /// What App Review asks to be said by the button: the trial or
    /// introductory price, the price, the period, and that it renews.
    private func terms(for package: Package) -> String {
        let product = package.storeProduct
        guard let period = product.subscriptionPeriod else {
            return "One payment of \(product.localizedPriceString), for good."
        }
        let price = "\(product.localizedPriceString) \(period.every)"
        let start: String
        switch intro(of: package) {
        case let intro? where intro.paymentMode == .freeTrial:
            start = "Free for \(intro.subscriptionPeriod.length), then \(price)."
        case let intro? where intro.paymentMode == .payUpFront:
            start = "\(intro.localizedPriceString) for the \(intro.subscriptionPeriod.first), then \(price)."
        case let intro? where intro.paymentMode == .payAsYouGo:
            let span = SubscriptionPeriod(value: intro.subscriptionPeriod.value * intro.numberOfPeriods, unit: intro.subscriptionPeriod.unit)
            start = "\(intro.localizedPriceString) \(intro.subscriptionPeriod.every) for \(span.length), then \(price)."
        default:
            start = "\(price)."
        }
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

/// What a sale can say on the RevenueCat offering's metadata, without an app
/// update: `eyebrow` replaces "Cue Super" over the title, `headline` the
/// title, and `badge` goes on the plan named by `badge_plan` (`monthly`,
/// `annual` or `lifetime`; `annual` when it's left out), which is then the
/// one chosen when the paywall opens.
extension Offering {
    var saleEyebrow: String? { Self.text(metadata["eyebrow"]) }

    var saleHeadline: String? { Self.text(metadata["headline"]) }

    var saleBadge: String? { Self.text(metadata["badge"]) }

    var saleBadgePlan: PackageType? {
        guard saleBadge != nil else { return nil }
        switch metadata["badge_plan"] as? String {
        case "monthly": return .monthly
        case "lifetime": return .lifetime
        default: return .annual
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// One plan: its name, price and period, the regular price struck through
/// under an introductory one, and a badge.
private struct PlanCard: View {
    let package: Package
    /// A lower introductory price this Apple Account can take.
    let intro: StoreProductDiscount?
    let badge: String?
    /// A sale's badge catches the light now and then.
    let shimmers: Bool
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                Text(name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.6))
                if intro != nil {
                    Text(package.storeProduct.localizedPriceString)
                        .font(.caption)
                        .strikethrough()
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(intro?.localizedPriceString ?? package.storeProduct.localizedPriceString)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(per)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: .capsule)
                        .modifier(Shimmer(isOn: shimmers))
                        .offset(y: -9)
                }
            }
            .contentShape(.rect)
            .scaleEffect(isSelected ? 1 : 0.96)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
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
        if let intro {
            return intro.paymentMode == .payUpFront ? intro.subscriptionPeriod.first : intro.subscriptionPeriod.every
        }
        return package.storeProduct.subscriptionPeriod?.every ?? "once"
    }

    private var accessibilityText: String {
        let regular = package.storeProduct.localizedPriceString
        let price = intro.map { "\($0.localizedPriceString) \(per), then \(regular)" } ?? "\(regular) \(per)"
        return [name, price, badge?.lowercased()].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A band of light that sweeps across the view every couple of seconds. Not
/// with Reduce Motion, and not on the Mac, where an animation that never
/// stops holds ~90 MB of GPU memory for as long as it runs.
private struct Shimmer: ViewModifier {
    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
        #else
        if isOn && !reduceMotion {
            content.phaseAnimator([false, true]) { view, isSweeping in
                view.overlay {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.45)
                            .offset(x: isSweeping ? proxy.size.width * 1.1 : -proxy.size.width * 0.55)
                    }
                    .clipShape(.capsule)
                    .allowsHitTesting(false)
                }
            } animation: { isSweeping in
                // Out to the far side after a pause, then straight back.
                isSweeping ? .easeInOut(duration: 0.8).delay(1.6) : nil
            }
        } else {
            content
        }
        #endif
    }
}

private extension SubscriptionPeriod {
    /// "a month", "a year"; "every 3 months" for a longer period.
    var every: String {
        value == 1 ? "a \(Self.name(of: unit))" : "every \(length)"
    }

    /// "first year", "first 3 months".
    var first: String {
        value == 1 ? "first \(Self.name(of: unit))" : "first \(length)"
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
