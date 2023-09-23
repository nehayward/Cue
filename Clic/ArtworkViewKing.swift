import Kingfisher
import SwiftUI
import SonosKit

struct ArtworkViewKing: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom
    @State var artworkURL: URL?

    var body: some View {
        KFImage(artworkURL)
            .placeholder {
                RoundedRectangle(cornerRadius: 4)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.ultraThinMaterial)
                    .shadow(radius: 2)
            }
            .cacheMemoryOnly()
            .fade(duration: 0.2)
            .retry(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))
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
                }
            }.task(id: group.coordinatorRoom.track.name) {
                print("Fetching Track")
                artworkURL = await sonosService.getArtwork(from: group.coordinatorRoom.track)
            }
    }
}

#Preview {
    ArtworkViewKing(group: .constant(.garage))
        .environment(SonosService())
}

