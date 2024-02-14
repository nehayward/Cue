import NukeUI
import SwiftUI
import SonosKit

struct ContentArtworkView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var content: PlayableContent?
    @State var artworkURL: URL?
    @State var size: Double = 24

    var body: some View {
        GeometryReader { proxy in
            LazyImage(url: artworkURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if state.isLoading {
                    RoundedRectangle(cornerRadius: 4)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.ultraThinMaterial)
                        .shadow(radius: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
            .overlay(alignment: .bottomTrailing) {
                if let content = content {
                    switch content.content.service {
                    case .apple:
                        Image(systemName: "apple.logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white.gradient)
                            .frame(width: size, height: size, alignment: .bottomTrailing)
                            .padding(size == 24 ? 16 : 4)
                            .shadow(radius: 10)
                    case .spotify:
                        Image(.spotifyLogo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white.gradient)
                            .frame(width: size, height: size, alignment: .bottomTrailing)
                            .padding(size == 24 ? 16 : 4)
                            .shadow(radius: 10)
                    case .airplay, .unknown:
                        EmptyView()
                            .padding([.trailing, .bottom], 12)
                    }
                }

                if content?.content.type == .favorite {
                    Image(systemName: "star.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white.gradient)
                        .frame(width: size, height: size, alignment: .bottomTrailing)
                        .padding(size == 24 ? 16 : 4)
                        .shadow(radius: 10)
                }
            }
            .task(id: content?.content.id) {
                if let content = content?.content, artworkURL == nil {
                    artworkURL = await sonosService.getArtwork(from: content)
                }
                if let artwork = content?.artwork {
                    artworkURL = artwork
                }
            }
            .onChange(of: proxy.size, initial: true) {
                if proxy.size.width <= 100 {
                    size = 16
                } else {
                    size = 24
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

//#Preview("Empty") {
//    ContentArtworkView(track: .constant(Track(trackID: "", name: "", TVMode: false)))
//        .environment(SonosService.shared)
//}
//
//#Preview("Dua Lipa") {
//    ContentArtworkView(track: .constant(Track(trackID: "6wf7Yu7cxBSPrRlWeSeK0Q", musicService: .spotify)))
//        .environment(SonosService.shared)
//}
//
//#Preview("White Background") {
//    ContentArtworkView(track: .constant(Track(trackID: "204669559", musicService: .apple)))
//        .environment(SonosService.shared)
//
//}
//
//#Preview("Dark Album") {
//    ContentArtworkView(track: .constant(Track(trackID: "7sjuNUjWtSqhbxJ3RAUffm", musicService: .spotify)))
//        .environment(SonosService.shared)
//}
//
