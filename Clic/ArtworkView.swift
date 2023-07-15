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
            default:
                RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(.ultraThinMaterial)
            }
        }
    }
}

#Preview {
    ArtworkView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")]))
        .environment(SonosService())
}

