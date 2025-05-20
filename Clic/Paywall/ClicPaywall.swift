import Analytics
import RevenueCatUI
import RevenueCat
import SwiftUI
import SubscriptionKit

struct ClicPaywall: View {
    @Environment(\.dismiss) var dismiss

    private var features = [
        (Icons.speaker.systemName, "Show All Devices", "Effortlessly manage all your Sonos devices in one place."),
        (Icons.mac.systemName, "Cross-Platform Experience", "Enjoy seamless control on iPadOS, macOS, and watchOS"),
        (Icons.liveActivity.systemName, "Live Activities", "Instantly adjust playback and volume from the lock screen."),
        (Icons.widgets.systemName, "Widgets", "Convenient home screen widgets for immediate playback control."),
        (Icons.watch.systemName, "Apple Watch", "Control your Sonos system with ease from your wrist."),
        (Icons.scenes.systemName, "Scenes", "Group rooms and set ideal volume with a single tap."),
        (Icons.shortcuts.systemName, "Apple Shortcuts", "Rapidly manage playback using the Shortcuts app.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Hero Section
                VStack(spacing: 8) {
                    Text("Clic Super")
                        .bold()
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Elevate your Sonos experience")
                        .foregroundStyle(.secondary)
                    
                }
                .padding(.top, 24)
                
                LazyVGrid(columns: [
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, element in
                        FeatureCard(
                            icon: element.0,
                            title: element.1,
                            description: element.2
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .fontDesign(.rounded)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.12, blue: 0.12),  // Dark emerald
                    Color(red: 0.02, green: 0.05, blue: 0.05)   // Darker emerald
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .originalTemplatePaywallFooter(purchaseCompleted: { customerInfo in
            Analytics.shared.track(.subscribed)
            dismiss()
        })
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
        .onAppear {
            Analytics.shared.track(.viewedPaywall)
        }
        .customizeWindowSizeForMacOS15()
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .bold()
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial.opacity(0.2))
        )
    }
}

#Preview {
    Text("HERE")
        .background(.red)
        .sheet(isPresented: .constant(true)) {
            ClicPaywall()
        }
}

fileprivate enum Icons {
    case watch
    case speaker
    case shortcuts
    case widgets
    case liveActivity
    case scenes
    case mac

//    init(number: Int) {
//        let option = number % 6
//        switch option {
//        case 0:
//            self = .watch
//        case 1:
//            self = .speaker
//        case 2:
//            self = .shortcuts
//        case 3:
//            self = .widgets
//        case 4:
//            self = .liveActivity
//        case 5:
//            self = .scenes
//        default:
//            self = .watch
//        }
//    }

    var systemName: String {
        switch self {
        case .watch:
            "applewatch"
        case .speaker:
            "hifispeaker.arrow.forward.fill"
        case .shortcuts:
            "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .widgets:
            "square.stack"
        case .scenes:
            "bolt.fill"
        case .liveActivity:
            "dot.radiowaves.left.and.right"
        case .mac:
            "apple.logo"
        }
    }
}

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
