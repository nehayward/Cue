import SonosKit
import SwiftUI

struct TrackContainerView: View {
    let group: GroupRoom
    var action: (() -> Void)?
    
    var body: some View {
            Button {
                guard let uri = group.coordinatorRoom.container?.id?.objectId,
                      let serviceID = group.coordinatorRoom.container?.id?.serviceId else { return }
                guard let (service, id, url) = MusicServiceParser.shared.lookup(uri: uri, serviceID: serviceID) else { return }
                action?()
            } label: {
                Text(group.coordinatorRoom.container?.name ?? "")
                    .font(.caption.smallCaps())
                    .lineLimit(1, reservesSpace: true)
            }
            .allowsHitTesting(false)
        // MARK: Add Back when you can do service lookup
//            .allowsHitTesting(group.coordinatorRoom.container?.type != "track")
            .tint(.secondary)
            .opacity(group.coordinatorRoom.container?.type == "track" ? 0 : 1)

    }
}


#Preview {
    TrackContainerView(group: GroupRoom.garage)
}
