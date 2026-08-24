import SonosKit
import SwiftUI

struct TrackContainerView: View {
    @Environment(Router.self) private var router: Router?
    @Environment(AlertService.self) private var alertService: AlertService?
    
    let group: GroupRoom
    
    var body: some View {
        Button {
            guard let objectId = group.coordinatorRoom.container?.id?.objectId,
                  let containerType = ContentType(group.coordinatorRoom.container?.type ?? "") else { return }
            let serviceID = group.coordinatorRoom.container?.id?.serviceId ?? ""
            Task {
                let service: MusicService
                let id: String
                let resolvedType: ContentType
                if let parsed = MusicServiceParser.shared.lookup(uri: objectId, serviceID: serviceID, type: containerType) {
                    (service, id, resolvedType) = parsed
                } else {
                    // serviceId missing — infer service from the currently playing track
                    let inferredService = group.coordinatorRoom.track.musicService
                    guard let parsed = MusicServiceParser.shared.parse(uri: objectId, service: inferredService) else { return }
                    service = inferredService
                    id = parsed.0
                    resolvedType = parsed.1 ?? containerType
                }
                guard let content = await SonosService.shared.contentLookup(id: id, type: resolvedType, service: service) else { return }
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
