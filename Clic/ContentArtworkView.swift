import NukeUI
import SwiftUI
import SonosKit
import MusicKit
import MusicSearchKit

struct ContentArtworkView: View {
    @Environment(SonosService.self) var sonosService

    var content: PlayableContent
    var showMusicSource: Bool = true
    @State var imageRequest: ImageRequest?
    var preferredSize: Int = 180

    var body: some View {
        Group {
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
                                if state.error != nil {
                                    Image(systemName: "music.note")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.regularMaterial)
                                        .frame(width: 24, height: 24)
                                        .transaction { transaction in
                                            transaction.animation = nil
                                        }
                                }
                            }
                    }
                }
                .priority(.veryHigh)
            }
            // MARK: For Screenshots
            //                #if DEBUG
            //                .overlay {
            //                    Rectangle()
            //                        .foregroundStyle(.regularMaterial)
            //                }
            //                #endif
            .clipShape(content.content.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
            .shadow(radius: 2)
            .overlay(alignment: .bottomTrailing) {
                if showMusicSource {
                    Group {
                        content.content.service.icon
                            .containerRelativeFrame(.horizontal) { size, axis in
                                size * 0.025
                            }
                            .padding(4)
                        if content.content.type == .favorite {
                            Image(systemName: "star.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white.gradient)
                                .containerRelativeFrame(.horizontal) { size, axis in
                                    size * 0.03
                                }
                                .padding(4)
                                .shadow(radius: 10)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .task(id: content.id) {
                guard !content.id.isEmpty else {
                    imageRequest = nil
                    return
                }

                // TODO: Clean this up.
                if let url = content.artwork, !(content.artwork?.absoluteString ?? "").contains("get") {
                    let request = URLRequest(url: url)
                    imageRequest = ImageRequest(urlRequest: request)
                    return
                }
                guard let artworkURL = await sonosService.getArtwork(from: content, size: preferredSize) else {
                    if let artworkURL = content.artwork {
                        let request = URLRequest(url: artworkURL)
                        imageRequest = ImageRequest(urlRequest: request)
                    }
                    return
                }

                let request = URLRequest(url: artworkURL)
                imageRequest = ImageRequest(urlRequest: request)
            }
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
