import SwiftUI
import SonosKit

struct ArtworkView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var group: GroupRoom

    var body: some View {
        AsyncImage(
            url: group.coordinatorRoom.track.artworkURL,
            transaction: Transaction(animation: .snappy)
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(radius: 2)
            default:
                RoundedRectangle(cornerRadius: 4)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.ultraThinMaterial)
                    .shadow(radius: 2)
            }
        }
    }
}

#Preview {
    ArtworkView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")]))
        .environment(SonosService())
}

