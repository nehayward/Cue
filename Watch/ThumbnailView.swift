import Nuke
import NukeUI
import SwiftUI
import SonosKit
import MusicKit
import MusicSearchKit

struct ThumbnailView: View {
    @Environment(SonosService.self) var sonosService
    
    var content: PlayableContent
    var showMusicSource: Bool = true
    @State var imageRequest: ImageRequest?
    var preferredSize: Int = 100
    
    var body: some View {
        LazyImage(request: imageRequest) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.ultraThinMaterial)
                    .shadow(radius: 2)
                    .overlay {
                        if state.error != nil {
                            Image(systemName: "music.note")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.foreground)
                                .frame(width: 24, height: 24)
                                .bold()
                                .transaction { transaction in
                                    transaction.animation = nil
                                }
                        }
                    }
            }
        }
        .transition(.opacity)
        .id(content.id)
        .clipShape([.artist, .libraryArtist].contains(content.content.type) ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
        .shadow(radius: 2)
        .overlay(alignment: .bottomTrailing) {
            content.content.service.icon
                .containerRelativeFrame(.horizontal) { size, axis in
                    size * 0.05
                }
                .padding(4)
                .shadow(radius: 10)
                .opacity(showMusicSource ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .task(id: content.id) {
            imageRequest = makeImageRequest(url: content.artwork, priority: .veryLow)
            let dataCache = try? DataCache(name: "com.clic.imageCache")
            
            if dataCache?.containsData(for: content.id) ?? false, ![.playlist, .libraryPlaylist].contains(content.content.type) {
//                print("Data is cached")
                return
            }
            
            guard !content.id.isEmpty else {
                imageRequest = nil
                return
            }
        
            
            if let url = content.artwork, !(content.artwork?.absoluteString ?? "").contains("get") {
                imageRequest = makeImageRequest(url: url)
                return
            }
            
            guard let artworkURL = await sonosService.getArtwork(from: content, size: preferredSize) else {
                if let artworkURL = content.artwork {
                    imageRequest = makeImageRequest(url: artworkURL)
                }
                return
            }
            if let url = content.artwork {
                ImagePipeline.shared.imageTask(with: url).cancel()
            }
            imageRequest = makeImageRequest(url: artworkURL)
        }
    }
    
    private func makeImageRequest(url: URL?, priority: ImageRequest.Priority = .veryHigh) -> ImageRequest {
        let request = ImageRequest(
            url: url,
            priority: priority,
            userInfo: [.imageIdKey: content.id]
        )
        
        return request
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
