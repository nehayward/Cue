import NukeUI
import SwiftUI
import SonosKit
import MusicKit
import MusicSearchKit

struct ContentArtworkView: View {
    @Binding var content: PlayableContent?
    @State var size: Double = 24

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let request = request() {
                    LazyImage(request: ImageRequest(urlRequest: request)) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else if state.isLoading {
                            RoundedRectangle(cornerRadius: 4)
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.ultraThinMaterial)
                                .shadow(radius: 2)
                        } else {
                            Rectangle()
                                .foregroundStyle(.accent.gradient.secondary)
                                .aspectRatio(contentMode: .fit)
                                .overlay {
                                    if content?.artwork == nil {
                                        Image(systemName: "music.note")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundStyle(.regularMaterial)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                        }
                    }
                }
            }
            .clipShape(content?.content.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
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
                    case .library:
                        Image(systemName: "books.vertical.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white.gradient)
                            .frame(width: size, height: size, alignment: .bottomTrailing)
                            .padding(size == 24 ? 16 : 4)
                            .shadow(radius: 10)
                    case .plex:
                        Image(.plex)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white.gradient)
                            .frame(width: size, height: size, alignment: .bottomTrailing)
                            .padding(size == 24 ? 16 : 4)
                            .shadow(radius: 10)
                    case .airplay, .unknown:
                        EmptyView()
                            .padding([.trailing, .bottom], 12)
                    case .tidal:
                        MediaSearchService.tidal.icon
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white.gradient)
                            .frame(width: size, height: size, alignment: .bottomTrailing)
                            .padding(size == 24 ? 16 : 4)
                            .shadow(radius: 10)
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

    private func request() -> URLRequest? {
        if let url = content?.artwork {
            var request = URLRequest(url: url)
            if content?.content.service == .plex {
                request.addValue("3zy3EmAvq8dmHdhfCd9z", forHTTPHeaderField: "X-Plex-Token")
            }
            return request
        }
        return nil
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
