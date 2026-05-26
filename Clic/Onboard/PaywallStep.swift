import SwiftUI

/// Final onboarding page — wraps `ClicPaywall` and overlays a Skip capsule
/// (top-leading, to avoid colliding with the paywall's own xmark dismiss).
struct PaywallStep: View {
    var finish: () -> Void

    var body: some View {
        ClicPaywall()
            .overlay(alignment: .topLeading) {
                Button(action: finish) {
                    Text("Skip")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding([.top, .leading])
            }
    }
}
