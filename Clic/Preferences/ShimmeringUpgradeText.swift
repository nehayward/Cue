import SwiftUI

/// "Upgrade to Lifetime" label, rendered with a static accent-color gradient.
/// Sits inline below the Clic Super badge in Preferences. An earlier version
/// used an animated highlight sweep, but that felt too aggressive for users
/// who are already paying subscribers — they're already loyal, the row just
/// needs to read as a tappable accent-colored CTA, not a flashing pitch.
struct ShimmeringUpgradeText: View {
    var body: some View {
        Text("Upgrade to Lifetime")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}
