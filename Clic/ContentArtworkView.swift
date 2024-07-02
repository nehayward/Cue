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
    @State var size: Double = 24

    var body: some View {
        Group {
            GeometryReader { proxy in
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
                        .transaction { transaction in
                            transaction.disablesAnimations = true
                        }
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
                .task(id: content.id) {
                    guard !content.id.isEmpty else {
                        imageRequest = nil
                        return
                    }

                    // TODO: Clean this up.
                    if let url = content.artwork, !(content.artwork?.absoluteString ?? "").contains("get") {
                        var request = URLRequest(url: url)
                        if content.content.service == .plex {
                            request.addValue("3zy3EmAvq8dmHdhfCd9z", forHTTPHeaderField: "X-Plex-Token")
                        }
                        imageRequest = ImageRequest(urlRequest: request)
                        return
                    }
                    guard let artworkURL = await sonosService.getArtwork(from: content.content, size: size == 16 ? 100 : 320) else {
                        // TODO: Add for Plex maybe abstract this
//                        if content.content.service == .plex {
//                            let urlRequest = URLRequest(url: artworkURL)
//                            request.addValue("3zy3EmAvq8dmHdhfCd9z", forHTTPHeaderField: "X-Plex-Token")
//                            imageRequest = ImageRequest(url: )
//                        }
                        if let artworkURL = content.artwork {
                            var request = URLRequest(url: artworkURL)
                            if content.content.service == .plex {
                                request.addValue("3zy3EmAvq8dmHdhfCd9z", forHTTPHeaderField: "X-Plex-Token")
                            }
                            imageRequest = ImageRequest(urlRequest: request)
                        }
                        return
                    }
                    
                    var request = URLRequest(url: artworkURL)
                    if content.content.service == .plex {
                        request.addValue("3zy3EmAvq8dmHdhfCd9z", forHTTPHeaderField: "X-Plex-Token")
                    }
                    imageRequest = ImageRequest(urlRequest: request)
                }
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
