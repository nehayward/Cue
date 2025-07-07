import SwiftUI
import NukeUI
import Nuke
import SonosKit
import MusicKit
import MusicSearchKit

struct LightArtworkView: View {
    var content: PlayableContent
    var id: String
    var contentType: ContentType
    var showMusicSource: Bool
    @State var thumbnail: URL?
    @State private var artworkTask: Task<Void, Never>?
    
    var body: some View {
        VStack {
            LazyImage(request: ImageRequest(url: thumbnail, userInfo: [.imageIdKey: content.id, .thumbnailKey: true])) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.ultraThinMaterial)
                        .shadow(radius: 2)
                        .overlay {
                            if content.thumbnail == nil || state.error != nil {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .bold()
                            }
                        }
                }
            }
        }
        .id(thumbnail)
        .clipShape(contentShape)
        .shadow(radius: 1)
        .overlay(alignment: .bottomTrailing) {
            if showMusicSource {
                OverlayIcons(content: content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
        .onAppear {
            artworkTask = Task {
                if ImagePipeline.shared.cache.containsCachedImage(for: ImageRequest(url: nil, userInfo: [.imageIdKey: content.id, .thumbnailKey: true])) {
                    return
                }
                print("Failed")
                guard let thumbnail = await SonosService.shared.getArtwork(from: content, size: 50) else {
                    if !Task.isCancelled {
                        self.thumbnail = content.artwork
                    } else {
                        print("Cancelled thumbnail download")
                    }
                    return
                }
                
                if !Task.isCancelled {
                    self.thumbnail = thumbnail
                } else {
                    print("Cancelled thumbnail download")
                }
            }
        }
        .onDisappear {
            artworkTask?.cancel()
            artworkTask = nil
        }
    }
    
    private var contentShape: some Shape {
        if [.artist, .libraryArtist, .artistRadio].contains(contentType) {
            return AnyShape(Circle())
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

fileprivate struct OverlayIcons: View {
    let content: PlayableContent  // Replace with your actual content type

    var body: some View {
        ZStack {
            content.content.service.icon
                .containerRelativeFrame(.horizontal) { size, _ in
#if targetEnvironment(macCatalyst)
                    size * 0.02
#else
                    size * 0.025
#endif
                }
                .padding(4)
                .shadow(radius: 2)
            
            if content.content.type == .favorite {
                Image(systemName: "star.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white.gradient)
                    .containerRelativeFrame(.horizontal) { size, _ in
                        size * 0.03
                    }
                    .padding(4)
                    .shadow(radius: 10)
            }
        }
    }
}

//
//imageRequest = makeImageRequest(url: content.artwork, priority: .veryLow)
////                let dataCache = try? DataCache(name: "com.clic.imageCache")
////                if dataCache?.containsData(for: content.id) ?? false, ![.playlist, .libraryPlaylist].contains(content.content.type) {
////                    imageRequest = ImageRequest(url: dataCache?.url(for: content.id))
////                    return
////                }
////
////                guard !content.id.isEmpty else {
////                    imageRequest = nil
////                    return
////                }
////
////
////                if let url = content.artwork, !(content.artwork?.absoluteString ?? "").contains("get") {
////                    imageRequest = makeImageRequest(url: url)
////                    return
////                }
////
////                guard let artworkURL = await SonosService.shared.getArtwork(from: content, size: preferredSize) else {
////                    if let artworkURL = content.artwork {
////                        imageRequest = makeImageRequest(url: artworkURL)
////                    }
////                    return
////                }
////                if let url = content.artwork {
////                    ImagePipeline.shared.imageTask(with: url).cancel()
////                }
////                imageRequest = makeImageRequest(url: artworkURL)
//          }
//  }
//
////    private func makeImageRequest(url: URL?, priority: ImageRequest.Priority = .veryHigh) -> ImageRequest {
////        let request = ImageRequest(
////            url: url,
////            priority: priority,
////            userInfo: [.imageIdKey: content.id]
////        )
////
////        return request
////    }
//}
