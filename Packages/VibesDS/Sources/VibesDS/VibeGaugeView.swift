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

    public var body: some View {
        ZStack {
            Circle()
                .stroke(
                    color.opacity(0.4),
                    lineWidth: lineWidth
                )
            if value > 0 {
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
                    .animation(.spring, value: value)
            }
        }
    }
}
