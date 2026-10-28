import OSLog
import RevenueCat
import SwiftUI
import SubscriptionKit

struct CuePaywall: View {
    @Environment(\.dismiss) var dismiss
    /// The gate that brought it up, if one did: a card at the top says
    /// what was held back, and its row in the table is lit.
    var reason: PaywallReason?
    /// The singleton rather than the environment, so the paywall can be shown
    /// from anywhere (onboarding included) without depending on what's
    /// installed above it.
    @State private var subscriptionService = SubscriptionService.shared

    /// The footer's plans load async and render when the offering arrives.
    /// When the paywall slides in (especially the onboarding case) the
    /// footer popping in mid-slide caused a janky shift.
    /// We hold the content invisible for ~280ms — long enough for the
    /// transition to settle and the offering to fetch — then fade it in. The
    /// background stays solid throughout so the user never sees an empty frame.
    @State private var contentVisible = false

    /// The offering the footer shows. When it doesn't load the paywall stays
    /// up, says so, and offers Try Again (RevenueCat's own footer closed the
    /// whole presentation instead).
    @State private var offering: Offering?
    @State private var offeringFailed = false

    private static let log = Logger(subsystem: "dance.cue", category: "paywall")

    /// Rows for the Free vs Super comparison table. Free column is intentionally
    /// blank for every paid capability — loss aversion lands harder when the gap
    /// is visceral. The player's wins lead (Cue is a player first), Sonos
    /// follows; iPad / Mac / TV / Vision collapse into the single-license
    /// footer. Only what Cue has today: no Scenes or Shortcuts yet.
    private let comparisonRows: [ComparisonRow] = [
        .init(label: "Unlimited downloads", description: "Plex & Subsonic songs", inFree: false, features: [.unlimitedDownloads, .downloads, .largePlaybackCache]),
        .init(label: "Every Sonos room", description: "Free plays on one room", inFree: false, features: [.allRooms]),
        .init(label: "Book downloads", description: "Plex & Audiobookshelf", inFree: false, features: [.bookDownloads]),
        .init(label: "Read along", description: "A book's words as it's read", inFree: false, features: [.bookTranscript])
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Hero Section
                VStack(alignment: .leading, spacing: 10) {
                    Text(offering?.saleEyebrow?.uppercased() ?? "CUE SUPER")
                        .font(.caption.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(Color.accentColor)
                    Text(offering?.saleHeadline ?? "Keep every song.")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Unlimited downloads on iPhone and Apple Watch, then every Sonos room.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

                if let reason {
                    PaywallReasonCard(reason: reason)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    ComparisonTable(rows: comparisonRows, highlighted: reason?.feature)
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
        .safeAreaInset(edge: .bottom) {
            PurchaseFooter(offering: offering, failed: offeringFailed) {
                Task { await loadOffering() }
            } purchased: {
                dismiss()
            }
        }
        // Hold content invisible until the slide-in settles, then fade in
        // together with the footer's offering load. See `contentVisible`
        // for the full reasoning.
        .opacity(contentVisible ? 1 : 0)
        // Cap the readable content (table + footer) at ~640pt so the layout
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
        // Super arriving any way closes it, not only a purchase made in the
        // footer: Restore Purchases, or StoreKit's answer for a purchase this
        // install's RevenueCat user doesn't know landing while it's up.
        .onChange(of: subscriptionService.subscription.isActive) { _, isActive in
            if isActive {
                dismiss()
            }
        }
        .task {
            await loadOffering()
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

    private func loadOffering() async {
        offeringFailed = false
        #if DEBUG
        if PaywallSalePreview.isOn {
            offering = PaywallSalePreview.offering
            return
        }
        #endif
        guard Purchases.isConfigured else {
            Self.log.error("paywall: RevenueCat isn't configured yet")
            offeringFailed = true
            return
        }
        do {
            offering = try await Purchases.shared.offerings().current
            if offering == nil {
                Self.log.error("paywall: no current offering")
                offeringFailed = true
            }
        } catch {
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey].map { String(describing: $0) } ?? "none"
            Self.log.error("paywall: offerings failed: \(error.localizedDescription, privacy: .public); underlying: \(underlying, privacy: .public)")
            offeringFailed = true
        }
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

    /// Pure black with whisper-quiet teal radials at opposite corners — the
    /// site at cue.dance is essentially #000 with the colorful work done by
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
    /// The gates the row stands for, to light it when one brought the
    /// paywall up.
    var features: Set<GatedFeature> = []
}

/// Free vs Super side-by-side. Free column is `—` for every row, Super is a
/// teal checkmark — anchors the table to the accent color used everywhere
/// else on the paywall (SUPER header, license footer, eyebrow).
struct ComparisonTable: View {
    let rows: [ComparisonRow]
    /// The gate the paywall opened for; its row is lit.
    var highlighted: GatedFeature?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.white.opacity(0.1))
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let isLit = highlighted.map(row.features.contains) ?? false
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.subheadline.weight(isLit ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(isLit ? 1 : 0.85))
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
                .padding(.vertical, 10)
                .background(isLit ? Color.accentColor.opacity(0.14) : .clear)

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
            Text("One license · Every Cue app")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
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
        .padding(.vertical, 10)
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
            CuePaywall()
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
                identifier: "com.super.cue.monthly",
                packageType: .monthly,
                storeProduct: Offering.monthly.toStoreProduct(),
                offeringIdentifier: "default",
                webCheckoutUrl: nil
            ),
            .init(
                identifier: "com.super.cue.annual",
                packageType: .annual,
                storeProduct: Offering.yearly.toStoreProduct(),
                offeringIdentifier: "default",
                webCheckoutUrl: nil
            )
        ],
        webCheckoutUrl: nil
    )
}
