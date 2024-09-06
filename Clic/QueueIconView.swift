import SwiftUI
import SonosKit

struct QueueIconView: View {
    var group: GroupRoom
    // TODO: Use for queue
    var body: some View {
        Text(group.coordinatorRoom.queue.count, format: .number)
    }
}
