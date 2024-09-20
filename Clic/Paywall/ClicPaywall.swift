import Analytics
import RevenueCatUI
import RevenueCat
import SwiftUI
import SubscriptionKit

struct ClicPaywall: View {
    @Environment(\.dismiss) var dismiss

    private var features = [
        (Icons.speaker.systemName, "Show All Devices", "Effortlessly manage all your Sonos devices in one place."),
        (Icons.liveActivity.systemName, "Live Activities + Dynamic Island", "Instantly adjust playback and volume from the lock screen."),
        (Icons.widgets.systemName, "Interactive Widgets", "Convenient home screen widgets for immediate playback control."),
        (Icons.watch.systemName, "Apple Watch", "Control your Sonos system with ease from your wrist."),
        (Icons.scenes.systemName, "Scenes", "Group rooms and set ideal volume with a single tap."),
        (Icons.shortcuts.systemName, "Apple Shortcuts", "Rapidly manage playback using the Shortcuts app.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Clic Super")
                    .bold()
                    .font(.largeTitle)
                    .foregroundStyle(.teal.gradient)
                    .padding(.vertical, 24)
                ForEach(Array(features.enumerated()), id: \.offset) { index, element in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: element.0)
                            .foregroundStyle(.teal.gradient)
                        VStack(alignment: .leading) {
                            Text(element.1)
                                .bold()
                                .font(.title3)
                                .foregroundStyle(.teal.gradient)
                            Text(element.2)
                                .lineLimit(2, reservesSpace: true)
                                .foregroundStyle(.primary.opacity(0.8))
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .fontDesign(.rounded)
            .saturation(1.2)
        }
        .frame(maxWidth: .infinity)
        .paywallFooter(condensed: true, purchaseCompleted: { customerInfo in
            Analytics.shared.track(.subscribed)
            dismiss()
        })
        .fontDesign(.rounded)
        .interactiveDismissDisabled()
        .overlay(alignment: .topTrailing) {
            Button("Dismiss", systemImage: "xmark.circle.fill", role: .cancel, action: {
                dismiss()
            })
            .labelStyle(.iconOnly)
            .padding([.top, .trailing])
            .font(.title)
            .saturation(0.5)
            .opacity(0.7)
        }
        .onAppear {
            Analytics.shared.track(.viewedPaywall)
        }
#if targetEnvironment(macCatalyst)
        .frame(width: 800, height: 1000)
#endif
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
            "hifispeaker.2.fill"
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
                offeringIdentifier: "default"
            ),
            .init(
                identifier: "com.super.clic.annual",
                packageType: .annual,
                storeProduct: Offering.yearly.toStoreProduct(),
                offeringIdentifier: "default"
            )
        ]
    )
}
