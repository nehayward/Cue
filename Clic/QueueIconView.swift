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
                      lineWidth: position > 99 ? 3 : 2)
        .overlay {
            if position < 100 {
                Text(position, format: .number)
                    .contentTransition(.numericText())
                    .opacity(position == 0 ? 0.4 : 1)
                    .font(.caption2)
                    .padding(.vertical, 4)
                    .bold()
                    .scaledToFit()
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
