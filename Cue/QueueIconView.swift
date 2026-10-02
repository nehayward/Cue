import SwiftUI
import VibesDS
import SonosKit

struct QueueIconView: View {
    var group: GroupRoom

    private var position: Double {
        Double(group.playbackService == .queue ? group.coordinatorRoom.track.position : 0)
    }

    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 24

    var body: some View {
        VibeGaugeView(value: position,
                      total: Double(group.coordinatorRoom.queueTotal),
                      color: .primary,
                      lineWidth: 2)
        .overlay {
            // Four digits don't fit inside the gauge: "1,000" wraps onto two
            // lines and spills past the ring. Past 999 the ring is shown alone.
            if position < 1000 {
                Text(position, format: .number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 4)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
                    .font(.caption2.monospacedDigit())
                    .contentTransition(.identity)
            }
        }
        .animation(.spring, value: group.coordinatorRoom.track.position)
        .fontDesign(.rounded)
        .frame(width: iconSize, height: iconSize)
        .accessibilityLabel("Queue")
    }
}

#Preview {
    QueueIconView(group: .garage)
}
