import SwiftUI
import VibesDS
import SonosKit

struct QueueIconView: View {
    var group: GroupRoom

    private var position: Double {
        Double(group.playbackService == .queue ? group.coordinatorRoom.track.position : 0)
    }

    private var total: Double {
        Double(group.coordinatorRoom.queueTotal)
    }

    // Last consistent position/total pair. Around queue mutations (opening the
    // queue sheet, tapping a track) Sonos can briefly report a stale or zero
    // NrTracks; drawing position over that total clamps the ring to full. Hold
    // the previous ratio until the numbers agree again (position <= total).
    @State private var ringValue: Double = 0
    @State private var ringTotal: Double = 0

    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 24

    var body: some View {
        VibeGaugeView(value: ringValue,
                      total: ringTotal,
                      color: .primary,
                      lineWidth: 2)
        .overlay {
            Text(position, format: .number)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 4)
                .allowsTightening(true)
                .contentTransition(.numericText())
                .font(.caption2.monospacedDigit())
                .contentTransition(.identity)
        }
        .animation(.spring, value: group.coordinatorRoom.track.position)
        .fontDesign(.rounded)
        .frame(width: iconSize, height: iconSize)
        .accessibilityLabel("Queue")
        .onAppear { syncRing() }
        .onChange(of: position) { syncRing() }
        .onChange(of: total) { syncRing() }
    }

    private func syncRing() {
        guard position <= total else { return }
        ringValue = position
        ringTotal = total
    }
}

#Preview {
    QueueIconView(group: .garage)
}
