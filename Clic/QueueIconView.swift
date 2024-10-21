import SwiftUI
import VibesDS
import SonosKit

struct QueueIconView: View {
    @Binding var group: GroupRoom
    
    private var position: Double {
        Double(group.playbackService == .queue ? group.coordinatorRoom.track.position : 0)
    }
    
    var body: some View {
        VibeGaugeView(value: position,
                      total: Double(group.coordinatorRoom.queueTotal),
                      color: .primary,
                      lineWidth: 2)
        .overlay {
            Text(position, format: .number)
                .contentTransition(.numericText())
                .opacity(position == 0 ? 0.4 : 1)
                .font(.caption2)
                .padding(.vertical, 4)
                .bold()
        }
        .animation(.spring, value: group.coordinatorRoom.track.position)
        .fontDesign(.rounded)
    }
}
