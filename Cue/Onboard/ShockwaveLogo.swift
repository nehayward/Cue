import SwiftUI

/// The welcome page's signature visual: the `FloatingAppIcon` surrounded by
/// concentric expanding rings that emanate like a sound wave. Used only on the
/// welcome splash; the discovery page uses a smaller, distinct `SearchPulse`.
struct ShockwaveLogo: View {
    var intensified: Bool = false
    var pulseHaptics: Bool = false
    /// When false, the rings stop animating (TimelineView is dropped). Keeps
    /// the logo present but stops CPU work for off-screen pages.
    var animateRings: Bool = true
    private let ringCount = 4
    private let cycleDuration: Double = 2.6

    var body: some View {
        ZStack {
            // Rings — TimelineView throttled to ~30fps. Only mounted when active
            // so off-screen pages don't burn CPU redrawing the rings forever.
            if animateRings {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    rings(t: t)
                }
            }

            // Soft glow halo (static — animation handled by the icon's drop shadow)
            Circle()
                .fill(Color.white.opacity(intensified ? 0.22 : 0.14))
                .frame(width: 220, height: 220)
                .blur(radius: 28)

            FloatingAppIcon()
                .frame(width: 168, height: 168)
        }
        // Layout reports a phone-friendly 280pt. The rings still RENDER up to
        // ~480pt (their inner `.frame()` sizes are unchanged) and the ZStack
        // doesn't clip — but the parent layout no longer thinks this view is
        // 460pt wide, which was bleeding the WelcomeStep horizontally and
        // pushing the dismiss-X past the screen's safe area.
        .frame(width: 280, height: 280)
        // The rings + glow are decorative; the inner FloatingAppIcon already
        // announces "Cue" as a single element. Hide everything else from
        // VoiceOver so it doesn't tab through a ring per row.
        .accessibilityElement(children: .contain)
        .task(id: pulseHaptics) {
            guard pulseHaptics else { return }
            let interval = cycleDuration / Double(ringCount)
            while !Task.isCancelled {
                HapticManager.shared.fireHaptic(.dataRefresh(intensity: 0.35))
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    @ViewBuilder
    private func rings(t: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<ringCount, id: \.self) { i in
                let stagger = Double(i) * (cycleDuration / Double(ringCount))
                let phase = ((t + stagger).truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
                let progress = CGFloat(phase)
                let fade = 1 - pow(progress, 0.85)
                let baseOpacity = intensified ? 0.85 : 0.65
                Circle()
                    .stroke(
                        Color.white.opacity(baseOpacity * fade),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 180 + 300 * progress, height: 180 + 300 * progress)
            }
        }
    }
}
