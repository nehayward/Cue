import SwiftUI
import NukeUI
import Nuke
import SonosKit
import MusicKit
import MusicSearchKit

struct LightArtworkView: View {
    var content: PlayableContent
    var contentType: ContentType
    var showMusicSource: Bool
    @State var thumbnail: URL?
  
    var body: some View {
        LazyImage(request: ImageRequest(url: thumbnail, userInfo: [.imageIdKey: content.imageKey])) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .shadow(radius: 2)
                    .overlay {
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .bold()
                            .opacity(state.error == nil ? 1 : 0)
                    }
            }
        }
        .id(thumbnail)
        .clipShape(.rect(cornerRadius: 4))
        .overlay(alignment: .bottomTrailing) {
            OverlayIcons(content: content)
                .opacity(showMusicSource ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
        .task {
            if ImagePipeline.shared.cache.containsCachedImage(for: ImageRequest(url: content.thumbnail, userInfo: [.imageIdKey: content.imageKey])) {
                return
            }
            
            guard let newThumbnail = await SonosService.shared.getArtwork(from: content, size: 50) else {
                self.thumbnail = content.artwork
                return
            }
            
            self.thumbnail = newThumbnail
        }
    }
}

fileprivate struct OverlayIcons: View {
    let content: PlayableContent

    var body: some View {
        content.content.service.icon
            .containerRelativeFrame(.horizontal) { size, _ in
                size * 0.03
            }
            .padding(2)
            .shadow(radius: 3)
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
