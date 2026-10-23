import SwiftUI
import VibesDS
import SonosKit

/// The queue gauge: how far through the queue playback is, with the
/// position in the middle. `PresentedQueueIconView` draws it for whatever
/// the player shows; `init(group:)` for one speaker.
struct QueueIconView: View {
    /// The current song's 1-based place; zero when it isn't playing from a
    /// queue.
    let position: Int
    let total: Int

    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 24

    init(position: Int, total: Int) {
        self.position = position
        self.total = total
    }

    /// A speaker's place in its own queue, while it plays from it.
    init(group: GroupRoom) {
        self.init(
            position: group.playbackService == .queue ? group.coordinatorRoom.track.position : 0,
            total: group.coordinatorRoom.queueTotal
        )
    }

    var body: some View {
        VibeGaugeView(value: Double(position),
                      total: Double(total),
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
                    .font(.caption2.monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring, value: position)
        .fontDesign(.rounded)
        .frame(width: iconSize, height: iconSize)
        .accessibilityLabel("Up Next")
    }
}

#Preview {
    QueueIconView(group: .garage)
}
