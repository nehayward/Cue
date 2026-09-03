import SwiftUI

/// Final onboarding page — wraps `CuePaywall`. The earlier Skip capsule was
/// removed because the wrapped paywall already exposes its own xmark dismiss
/// (top-trailing); a parallel Skip read as a competing escape hatch and made
/// the upgrade decision feel optional in a way that softened conversion.
struct PaywallStep: View {
    var body: some View {
        CuePaywall()
    }
}
