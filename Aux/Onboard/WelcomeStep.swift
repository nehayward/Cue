import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The first onboarding page — pure splash. ShockwaveLogo + brand + tagline
/// + a single `Get Started` pill. No discovery state, no Sonos integration —
/// tapping the pill just advances to `DiscoveryStep`.
struct WelcomeStep: View {
    @State private var logoIn = false
    @State private var brandIn = false
    @State private var taglineIn = false
    @State private var ctaIn = false
    var advance: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ShockwaveLogo(pulseHaptics: logoIn, animateRings: true)
                .scaleEffect(logoIn ? 1 : 0.55)
                .opacity(logoIn ? 1 : 0)
                .blur(radius: logoIn ? 0 : 12)
                .frame(maxHeight: 320)

            VStack(spacing: 10) {
                Text("Clic")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.15), radius: 18)
                    .opacity(brandIn ? 1 : 0)
                    .offset(y: brandIn ? 0 : 18)

                Text("A premium Sonos companion.\nNo lag. No hassle. Just music.")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(taglineIn ? 1 : 0)
                    .offset(y: taglineIn ? 0 : 14)

                Text(platformLine)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
                    .opacity(taglineIn ? 1 : 0)
                    .offset(y: taglineIn ? 0 : 14)
            }
            .padding(.top, 8)

            Spacer(minLength: 24)

            PrimaryPillButton(title: "Get Started", action: advance)
                .opacity(ctaIn ? 1 : 0)
                .offset(y: ctaIn ? 0 : 32)
                .padding(.horizontal, 56)
                .padding(.bottom, 56)
        }
        .task {
            HapticManager.shared.fireHaptic(.buttonPress)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { logoIn = true }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.4)) {
                brandIn = true
                taglineIn = true
            }
            try? await Task.sleep(for: .milliseconds(260))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { ctaIn = true }
        }
    }

    /// iPhone screens are tight enough that the "Built for Apple devices —"
    /// prefix wraps awkwardly; the device list alone reads cleaner. iPad and
    /// Mac get the full marketing line.
    private var platformLine: String {
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return "iPhone, iPad, Watch, TV, and Mac."
        }
        #endif
        return "Built for Apple devices — iPhone, iPad, Watch, TV, and Mac."
    }
}
