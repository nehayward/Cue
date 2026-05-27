import Analytics
import RevenueCatUI
import RevenueCat
import SwiftUI
import SubscriptionKit

struct ClicPaywall: View {
    @Environment(\.dismiss) var dismiss

    /// RC's `originalTemplatePaywallFooter` loads pricing async and renders
    /// when the offering arrives. When the paywall slides in (especially the
    /// onboarding case) the footer popping in mid-slide caused a janky shift.
    /// We hold the content invisible for ~280ms — long enough for the
    /// transition to settle and the offering to fetch — then fade it in. The
    /// background stays solid throughout so the user never sees an empty frame.
    @State private var contentVisible = false

    /// Rows for the Free vs Super comparison table. Free column is intentionally
    /// blank for every paid capability — loss aversion lands harder when the gap
    /// is visceral. Top rows are the two visceral wins (speakers + lock-screen);
    /// Watch / iPad / Mac / TV / Vision collapse into the single-license footer.
    private let comparisonRows: [ComparisonRow] = [
        .init(label: "All your speakers", inFree: false),
        .init(label: "Lock Screen controls", description: "Widgets + Live Activities", inFree: false),
        .init(label: "Apple Watch", description: "Full control from your wrist", inFree: false),
        .init(label: "Scenes", description: "One-tap automations", inFree: false),
        .init(label: "Apple Shortcuts", inFree: false)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("A premium Sonos companion.")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                    Text("No lag. No hassle. Just music.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))

                    socialProof
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 24)

                VStack(spacing: 12) {
                    Text("WHAT YOU GET")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.accentColor)

                    ComparisonTable(rows: comparisonRows)
                }
                .padding(.horizontal)
                .padding(.top, 4)

                trustStrip
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            .padding(.bottom)
            .fontDesign(.rounded)
        }
        .frame(maxWidth: .infinity)
        .originalTemplatePaywallFooter(purchaseCompleted: { customerInfo in
            Analytics.shared.track(.subscribed)
            dismiss()
        })
        // Hold content invisible until the slide-in settles, then fade in
        // together with the RC footer's offering load. See `contentVisible`
        // for the full reasoning.
        .opacity(contentVisible ? 1 : 0)
        // Cap the readable content (table + RC footer) at ~640pt so the layout
        // reads as a centered column on iPad/Mac/Catalyst fullScreenCover —
        // without this the comparison table and "Try free" CTA stretched the
        // entire window width and looked unmoored. On iPhone the device width
        // is below the cap so this is a no-op. The background applies *after*
        // the cap so the black + teal radials still fill the whole window.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(paywallBackground)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .overlay(alignment: .topTrailing) {
            Button("Dismiss", systemImage: "xmark.circle.fill", role: .cancel, action: {
                dismiss()
            })
            .labelStyle(.iconOnly)
            .padding([.top, .trailing])
            .font(.title)
            .foregroundStyle(.secondary)
        }
        #if targetEnvironment(macCatalyst)
        // SwiftUI's `.keyboardShortcut(.cancelAction)` doesn't reliably reach
        // the first responder inside a sheet on Mac Catalyst — we drop down to
        // a UIKeyCommand-backed VC that's guaranteed to receive Escape.
        .background {
            EscapeKeyCatcher { dismiss() }
                .frame(width: 0, height: 0)
        }
        #endif
        .onAppear {
            Analytics.shared.track(.viewedPaywall)
        }
        .task {
            // 280ms is enough for WelcomeScreen's slideTransition to finish
            // (~250ms default spring) and for RC to typically resolve the
            // offering. Tuned by eye — shorter felt rushed, longer felt slow.
            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.easeOut(duration: 0.32)) {
                contentVisible = true
            }
        }
        .customizeWindowSizeForMacOS15()
    }

    /// Subscription-anxiety strip — answers three objections (lock-in,
    /// household sharing, ad creep) in one scannable row. Sits at the bottom
    /// of the readable content to address the doubts that kill conversion
    /// right before the user taps the CTA.
    private var trustStrip: some View {
        HStack(spacing: 16) {
            trustItem(icon: "checkmark.circle.fill", label: "Cancel anytime")
            trustItem(icon: "person.2.fill", label: "Family Sharing")
            trustItem(icon: "hand.raised.fill", label: "No ads, ever")
        }
        .frame(maxWidth: .infinity)
    }

    private func trustItem(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    /// App Store rating + review count. Verifiable social proof beats vanity
    /// member counts because users can cross-check it. Update the numbers from
    /// App Store Connect — the rating is hardcoded rather than fetched because
    /// dynamic StoreKit rating fetch isn't worth the runtime overhead for a
    /// number that changes glacially.
    private var socialProof: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text("4.4")
                .foregroundStyle(.white)
                .bold()
            Text("·")
                .foregroundStyle(.white.opacity(0.4))
            Text("250+ App Store reviews")
                .foregroundStyle(.white.opacity(0.7))
        }
        .font(.subheadline)
    }

    /// Pure black with whisper-quiet teal radials at opposite corners — the
    /// site at clic.dance is essentially #000 with the colorful work done by
    /// card borders, not the page background. Earlier iterations used a
    /// saturated mesh that overpowered the cards; this stays out of the way.
    private var paywallBackground: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 600
            )

            RadialGradient(
                colors: [Color.accentColor.opacity(0.06), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 600
            )
        }
        .ignoresSafeArea()
    }
}

struct ComparisonRow {
    let label: String
    var description: String? = nil
    let inFree: Bool
}

/// Free vs Super side-by-side. Free column is `—` for every row, Super is a
/// teal checkmark — anchors the table to the accent color used everywhere
/// else on the paywall (SUPER header, license footer, eyebrow).
struct ComparisonTable: View {
    let rows: [ComparisonRow]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.white.opacity(0.1))
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                        if let description = row.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    cellIcon(filled: row.inFree, dim: true)
                        .frame(width: 80)

                    cellIcon(filled: true, dim: false)
                        .frame(width: 80)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < rows.count - 1 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }

            licenseFooter
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// Single-license callout pinned to the bottom of the table — answers
    /// "do I have to buy this again on my iPad?" without making the user wonder.
    private var licenseFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "infinity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text("One license · Every Apple platform")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.accentColor.opacity(0.08))
    }

    private var header: some View {
        HStack {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Free")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 80)

            Text("SUPER")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Color.accentColor)
                .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func cellIcon(filled: Bool, dim: Bool) -> some View {
        if filled {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(dim ? .white.opacity(0.4) : Color.accentColor)
        } else {
            Text("—")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}

#Preview {
    Text("HERE")
        .background(.red)
        .sheet(isPresented: .constant(true)) {
            ClicPaywall()
        }
}

#if targetEnvironment(macCatalyst)
/// Hosts a UIViewController that registers a UIKeyCommand for the Escape key.
/// SwiftUI's `.keyboardShortcut` doesn't reliably propagate through sheet
/// presentation on Catalyst, but a first-responder VC with `keyCommands` does.
private struct EscapeKeyCatcher: UIViewControllerRepresentable {
    let onEscape: () -> Void

    func makeUIViewController(context: Context) -> EscapeKeyViewController {
        let vc = EscapeKeyViewController()
        vc.onEscape = onEscape
        return vc
    }

    func updateUIViewController(_ vc: EscapeKeyViewController, context: Context) {
        vc.onEscape = onEscape
    }
}

private final class EscapeKeyViewController: UIViewController {
    var onEscape: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape))]
    }

    @objc private func handleEscape() {
        onEscape?()
    }
}
#endif

extension Offering {
    private static let monthly = TestStoreProduct(
        localizedTitle: "Monthly",
        price: 1.99,
        localizedPriceString: "$4.99",
        productIdentifier: "$rc_monthly",
        productType: .autoRenewableSubscription,
        localizedDescription: "A product description."
    )

    private static let yearly = TestStoreProduct(
        localizedTitle: "Yearly",
        price: 14.99,
        localizedPriceString: "$14.99",
        productIdentifier: "$rc_yearly",
        productType: .autoRenewableSubscription,
        localizedDescription: "A product description."
    )

    static let offering = Offering(
        identifier: "monthly and yearly",
        serverDescription: "Annual",
        metadata: [:],
        availablePackages: [
            .init(
                identifier: "com.super.clic.monthly",
                packageType: .monthly,
                storeProduct: Offering.monthly.toStoreProduct(),
                offeringIdentifier: "default",
                webCheckoutUrl: nil
            ),
            .init(
                identifier: "com.super.clic.annual",
                packageType: .annual,
                storeProduct: Offering.yearly.toStoreProduct(),
                offeringIdentifier: "default",
                webCheckoutUrl: nil
            )
        ],
        webCheckoutUrl: nil
    )
}
