import SwiftUI

public struct VibeGaugeView: View {
    var value: Double
    var total: Double
    var color: Color
    var lineWidth: CGFloat = 2
    
    public init(value: Double, total: Double, color: Color, lineWidth: CGFloat) {
        self.value = value
        self.total = total
        self.color = color
        self.lineWidth = lineWidth
    }

    /// No animation on the Mac. The play buttons' rings (one per playing room
    /// in the sidebar) redraw from a running clock once a second, and each
    /// redraw started a spring: a steady animation in the main window for a
    /// step of under a pixel, where any animated redraw is a GPU-memory risk.
    private var progressAnimation: Animation? {
        #if targetEnvironment(macCatalyst)
        nil
        #else
        .spring
        #endif
    }

    public var body: some View {
        ZStack {
            // Explicit alpha on the concrete color rather than the hierarchical
            // `.secondary` level. This track is a full circle at the same line
            // width as the progress arc, so anything that re-resolves the
            // hierarchy at full strength — glass adapting to a new backdrop, or
            // a transition snapshot that drops vibrancy — draws it as a
            // complete ring and reads as a gauge flashing to 100%.
            Circle()
                .stroke(
                    color.opacity(0.25),
                    lineWidth: lineWidth
                )
            if value > 0 && total > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(min(value/total, 1.0)))
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(progressAnimation, value: value)
            }
        }
    }
}
