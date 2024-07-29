import NukeUI
import SwiftUI
import SonosKit
import MusicKit
import MusicSearchKit

struct ThumbnailView: View {
    @Environment(SonosService.self) var sonosService

    var content: PlayableContent
    @State var imageRequest: ImageRequest?
    @State var size: Double = 16

    var body: some View {

        Group {
            LazyImage(request: imageRequest) { state in
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
                            Image(systemName: "music.note")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.regularMaterial)
                                .frame(width: 24, height: 24)
                        }
                }
            }
            .processors([.resize(width: 40)])
            .shadow(radius: 2)
        }
//        // MARK: For Screenshots
//        #if DEBUG
//        .overlay {
//            Rectangle()
//                .foregroundStyle(.regularMaterial)
//        }
//        #endif
        .clipShape(content.content.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
        .shadow(radius: 2)
        .overlay(alignment: .bottomTrailing) {
            Group {
                content.content.service.icon
                    .frame(width: size, height: size, alignment: .bottomTrailing)
                    .padding(size == 24 ? 16 : 4)

                if content.content.type == .favorite {
                    Image(systemName: "star.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white.gradient)
                        .frame(width: size, height: size, alignment: .bottomTrailing)
                        .padding(size == 24 ? 16 : 4)
                        .shadow(radius: 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .task(id: content.id) {
            if content.artwork != nil, !(content.artwork?.absoluteString ?? "").contains("get") {
                imageRequest = ImageRequest(url: content.artwork)
                return
            }
            guard let artworkURL = await sonosService.getArtwork(from: content.content, size: 100) else {
                imageRequest = ImageRequest(url: content.artwork)
                return
            }
            imageRequest = ImageRequest(url: artworkURL)
        }
    }
}
