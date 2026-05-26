import SwiftUI

/// "Upgrade to Lifetime" label with a slow gold highlight that sweeps across
/// the text. Used inline below the Clic Super badge in Preferences.
///
/// Implemented as a `LinearGradient` on `.foregroundStyle` whose `startPoint`
/// and `endPoint` UnitPoints animate together on a 2.4s ease-in-out loop —
/// cheaper than a TimelineView + mask combo and stays smooth in a Form row.
struct ShimmeringUpgradeText: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Text("Upgrade to Lifetime")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor,
                        Color.primary.opacity(0.85),  // subtle on-brand highlight
                        Color.accentColor
                    ],
                    startPoint: UnitPoint(x: phase - 0.6, y: 0.5),
                    endPoint: UnitPoint(x: phase + 0.6, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    phase = 1.0
                }
            }
    }
}
