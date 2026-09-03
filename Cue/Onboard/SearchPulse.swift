import SwiftUI

/// Compact radar/pulse animation, used on the discovery page in idle +
/// searching states. Smaller than the welcome page's `ShockwaveLogo` and
/// visually distinct — concentric rings around a central antenna icon.
struct SearchPulse: View {
    var isAnimating: Bool
    /// Latches to `true` once `isAnimating` is first set, and *stays* true.
    /// Without this, the rings stop animating the instant the parent flips
    /// `discoveryStatus` to `.found` — but the view itself is still on
    /// screen, fading out via the parent's ZStack opacity transition. The
    /// "motion stops, then fade" sequence reads as a frame drop. Latching
    /// keeps the rings moving until the view actually unmounts.
    @State private var hasAnimated = false
    private let ringCount = 3
    private let cycleDuration: Double = 2.4

    var body: some View {
        ZStack {
            if isAnimating || hasAnimated {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<ringCount, id: \.self) { i in
                            let stagger = Double(i) * (cycleDuration / Double(ringCount))
                            let phase = ((t + stagger).truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
                            let progress = CGFloat(phase)
                            let fade = 1 - pow(progress, 0.9)
                            Circle()
                                .stroke(Color.accentColor.opacity(0.55 * fade),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 70 + 180 * progress, height: 70 + 180 * progress)
                        }
                    }
                }
            }

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 110, height: 110)
                    .blur(radius: 18)
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    }
                    .frame(width: 96, height: 96)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor, isActive: isAnimating || hasAnimated)
            }
        }
        .frame(width: 280, height: 280)
        // The discovery page's header text already announces "Searching for
        // Sonos speakers…" / etc., so the pulse itself is purely decorative.
        .accessibilityHidden(true)
        .onAppear { if isAnimating { hasAnimated = true } }
        .onChange(of: isAnimating) { _, new in if new { hasAnimated = true } }
    }
}
