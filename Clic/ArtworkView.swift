import SwiftUI
import SonosKit

struct ArtworkView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

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
                    .overlay(alignment: .bottomTrailing) {
                        switch group.coordinatorRoom.track.musicService {
                        case .apple:
                            Image(systemName: "apple.logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.thickMaterial)
                                .frame(width: 16, height: 16)
                                .padding([.trailing, .bottom], 4)
                        case .spotify:
                            Image(.spotifyLogo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.thickMaterial)
                                .frame(width: 16, height: 16)
                                .padding([.trailing, .bottom], 4)
                        case .airplay, .unknown:
                            EmptyView()
                        }
                    }
            case .failure:
                EmptyView()
                    .overlay(alignment: .center) {
                        VStack {
                            Text(group.coordinatorRoom.track.artworkURL?.description ?? "FAILED")
                            Text("Failed")
                        }
                    }
            default:
                RoundedRectangle(cornerRadius: 4)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.ultraThinMaterial)
                    .shadow(radius: 2)
                    .overlay(alignment: .center) {
                        Text(group.coordinatorRoom.track.artworkURL?.description ?? "Default")
                    }
            }
        }
    }
}

//#Preview {
//    ArtworkView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")], coordinatorRoom: .garage))
//        .environment(SonosService())
//}

