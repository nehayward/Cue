import SwiftUI
import SonosKit

struct ArtworkDebugView: View {
    var sonosService: SonosService
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
    ArtworkDebugView(sonosService: SonosService(), group: GroupRoom(id: "", coordinatorID: "", rooms: [.garage], coordinatorRoom: .garage))
        .environment(SonosService())
}

