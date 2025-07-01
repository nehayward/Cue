import Nuke
import NukeUI
import SwiftUI
import SonosKit
import MusicKit
import MusicSearchKit

struct ContentArtworkView: View {
    var content: PlayableContent
    var showMusicSource: Bool = true
    var preferredSize: Int = 100
    
    @State private var imageRequest: ImageRequest?

    var body: some View {
        LazyImage(request: imageRequest) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.ultraThinMaterial)
                    .shadow(radius: 2)
                    .overlay {
                        if content.thumbnail == nil {
                            Image(systemName: "music.note")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.foreground)
                                .frame(width: 24, height: 24)
                                .bold()
                        }
                    }
            }
        }
        .clipShape(contentShape)
        .overlay(alignment: .bottomTrailing) {
            if showMusicSource {
                overlayIcons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .task(id: content.id) {
            let cachedImageRequest = makeImageRequest(url: content.thumbnail, priority: .veryLow)
            self.imageRequest = cachedImageRequest
            if ImagePipeline.shared.cache.containsData(for: cachedImageRequest), ![.playlist, .libraryPlaylist].contains(content.content.type) {
                return
            }

            guard !content.id.isEmpty else {
                imageRequest = nil
                return
            }
        
            let url = preferredSize >= 100 ? content.artwork : content.thumbnail
            if let url, !(content.thumbnail?.absoluteString ?? "").contains("get") {
                imageRequest = makeImageRequest(url: url)
                return
            }
            
            guard let artworkURL = await SonosService.shared.getArtwork(from: content, size: preferredSize) else {
                if let artworkURL = content.thumbnail {
                    imageRequest = makeImageRequest(url: artworkURL)
                }
                return
            }
            if let url = content.thumbnail {
                ImagePipeline.shared.imageTask(with: url).cancel()
            }
            imageRequest = makeImageRequest(url: artworkURL)
        }
    }
    
    private func makeImageRequest(url: URL?, priority: ImageRequest.Priority = .veryHigh) -> ImageRequest {
        let request = ImageRequest(
            url: url,
            processors: [
                ImageProcessors.Resize(
                    size: CGSize(width: preferredSize, height: preferredSize),
                    contentMode: .aspectFit
                )
            ],
            priority: priority,
            userInfo: [.imageIdKey: content.id]
        )
        
        return request
    }
    
    private var contentShape: some Shape {
        if [.artist, .libraryArtist, .artistRadio].contains(content.content.type) {
            return AnyShape(Circle())
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 4))
        }
    }
    
    @ViewBuilder
    private var overlayIcons: some View {
        GeometryReader { proxy in
            ZStack {
                content.content.service.icon
                    .frame(width: proxy.size.width * 0.25, height: proxy.size.width * 0.25)
                    .shadow(radius: 1)
                    .padding(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                
                if [.songRadio, .radio, .artistRadio].contains(content.content.type) {
                    Image(systemName: "radio.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width * 0.25, height: proxy.size.width * 0.25)
                        .shadow(radius: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .foregroundStyle(.bar)
                        .tint(.white)
                        .padding(2)
                        .environment(\.colorScheme, .light)
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
