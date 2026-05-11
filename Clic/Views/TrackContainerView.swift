import SonosKit
import SwiftUI

struct TrackContainerView: View {
    @Environment(Router.self) private var router: Router?
    @Environment(AlertService.self) private var alertService: AlertService?
    
    let group: GroupRoom
    
    var body: some View {
        Button {
            guard let uri = group.coordinatorRoom.container?.id?.objectId,
                  let serviceID = group.coordinatorRoom.container?.id?.serviceId,
                  let type = ContentType(group.coordinatorRoom.container?.type ?? "") else { return }
            guard let (service, id, type) = MusicServiceParser.shared.lookup(uri: uri, serviceID: serviceID, type: type) else { return }
            Task {
                guard let content = await SonosService.shared.contentLookup(id: id, type: type, service: service) else { return }
                router?.presentedSheet = .mediaDetail(content: content, group: group)
            }
        } label: {
            Text(group.coordinatorRoom.container?.name ?? "")
                .font(.caption.smallCaps())
                .lineLimit(1, reservesSpace: true)
        }
        .tint(.secondary)
        .opacity(group.coordinatorRoom.container?.type == "track" ? 0 : 1)
    }
}


#Preview {
    TrackContainerView(group: GroupRoom.garage)
}
