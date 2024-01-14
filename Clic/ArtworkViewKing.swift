import Kingfisher
import NukeUI
import SwiftUI
import SonosKit

struct ArtworkViewKing: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom
    @State var artworkURL: URL?

    var body: some View {
        LazyImage(url: artworkURL) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.ultraThinMaterial)
                    .shadow(radius: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
        .overlay(alignment: .bottomTrailing) {
            switch group.coordinatorRoom.track.musicService {
            case .apple:
                Image(systemName: "apple.logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white.gradient)
                    .frame(width: 16, height: 16)
                    .padding([.trailing, .bottom], 4)
            case .spotify:
                Image(.spotifyLogo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white.gradient)
                    .frame(width: 16, height: 16)
                    .padding([.trailing, .bottom], 4)
            case .airplay, .unknown:
                EmptyView()
                    .padding([.trailing, .bottom], 4)
            }
        }
        .task(id: group.coordinatorRoom.track.name) {
            print("Fetching Track for \(group.nameWithCount)")
            artworkURL = await sonosService.getArtwork(from: group.coordinatorRoom.track)
        }
    }
}

#Preview {
    ArtworkViewKing(group: .constant(.garage))
        .environment(SonosService())
}

