//import SwiftUI
//import Kingfisher
//import SonosKit
//import MusicKit
//import MusicSearchKit
//
//struct KFContentArtworkView: View {
//    var content: PlayableContent
//    var showMusicSource: Bool = true
//    var preferredSize: Int = 50
//    
//    @State private var source: KF.ImageResource?
//    
//    var body: some View {
//        VStack {
//            if let source {
//                KFImage(source: .network(source))
//                    .forceTransition(false)
//                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 50, height: 50)))
//                    .backgroundDecode()
//                    .interpolation(.low)
//                    .cancelOnDisappear(true)
//                    .fade(duration: 0)
//                    .placeholder {
//                        placeholderView
//                    }
//                    .resizable()
//                    .scaledToFill()
//                    .frame(width: 50, height: 50)
//                    .clipShape(contentShape)
//                    .overlay(alignment: .bottomTrailing) {
//                        if showMusicSource {
//                            overlayIcons
//                        }
//                    }
//
//            } else {
//                placeholderView
//                    .clipShape(contentShape)
//                    .overlay(alignment: .bottomTrailing) {
//                        if showMusicSource {
//                            overlayIcons
//                        }
//                    }
//            }
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
//        .task(id: content.id) {
//            guard !content.id.isEmpty, let thumbnail = content.thumbnail else {
//                return
//            }
//            
//            let cache = ImageCache.default
//            if cache.isCached(forKey: content.id, processorIdentifier: DownsamplingImageProcessor(size: CGSize(width: 50, height: 50)).identifier) {
//                print("Cached")
//                source = KF.ImageResource(downloadURL: thumbnail, cacheKey: content.id)
//                return
//            }
//            
//            if !(content.thumbnail?.absoluteString ?? "").contains("get") {
//                source = KF.ImageResource(downloadURL: thumbnail, cacheKey: content.id)
//            } else {
//                if let fetchedURL = await SonosService.shared.getArtwork(from: content, size: preferredSize) {
//                    source = KF.ImageResource(downloadURL: fetchedURL, cacheKey: content.id)
//                } else {
//                    source = KF.ImageResource(downloadURL: thumbnail, cacheKey: content.id)
//                }
//            }
//        }
//    }
//    
//    @ViewBuilder
//    private var placeholderView: some View {
//        Rectangle()
//            .aspectRatio(contentMode: .fit)
//            .foregroundStyle(.ultraThinMaterial)
//            .shadow(radius: 2)
//            .overlay {
//                if content.artwork == nil {
//                    Image(systemName: "music.note")
//                        .resizable()
//                        .scaledToFit()
//                        .foregroundStyle(.secondary)
//                        .frame(width: 16, height: 16)
//                        .bold()
//                }
//            }
//    }
//    
//    private var contentShape: some Shape {
//        if [.artist, .libraryArtist, .artistRadio].contains(content.content.type) {
//            return AnyShape(Circle())
//        } else {
//            return AnyShape(RoundedRectangle(cornerRadius: 4))
//        }
//    }
//    
//    @ViewBuilder
//    private var overlayIcons: some View {
//        GeometryReader { proxy in
//            ZStack {
//                content.content.service.icon
//                    .frame(width: proxy.size.width * 0.25, height: proxy.size.width * 0.25)
//                    .shadow(radius: 1)
//                    .padding(2)
//                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
//                
//                if [.songRadio, .radio, .artistRadio].contains(content.content.type) {
//                    Image(systemName: "radio.fill")
//                        .resizable()
//                        .aspectRatio(contentMode: .fit)
//                        .frame(width: proxy.size.width * 0.25, height: proxy.size.width * 0.25)
//                        .shadow(radius: 1)
//                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
//                        .foregroundStyle(.bar)
//                        .tint(.white)
//                        .padding(2)
//                        .environment(\.colorScheme, .light)
//                }
//            }
//        }
//    }
//}
//
////
////imageRequest = makeImageRequest(url: content.artwork, priority: .veryLow)
//////                let dataCache = try? DataCache(name: "com.clic.imageCache")
//////                if dataCache?.containsData(for: content.id) ?? false, ![.playlist, .libraryPlaylist].contains(content.content.type) {
//////                    imageRequest = ImageRequest(url: dataCache?.url(for: content.id))
//////                    return
//////                }
//////
//////                guard !content.id.isEmpty else {
//////                    imageRequest = nil
//////                    return
//////                }
//////
//////
//////                if let url = content.artwork, !(content.artwork?.absoluteString ?? "").contains("get") {
//////                    imageRequest = makeImageRequest(url: url)
//////                    return
//////                }
//////
//////                guard let artworkURL = await SonosService.shared.getArtwork(from: content, size: preferredSize) else {
//////                    if let artworkURL = content.artwork {
//////                        imageRequest = makeImageRequest(url: artworkURL)
//////                    }
//////                    return
//////                }
//////                if let url = content.artwork {
//////                    ImagePipeline.shared.imageTask(with: url).cancel()
//////                }
//////                imageRequest = makeImageRequest(url: artworkURL)
////          }
////  }
////
//////    private func makeImageRequest(url: URL?, priority: ImageRequest.Priority = .veryHigh) -> ImageRequest {
//////        let request = ImageRequest(
//////            url: url,
//////            priority: priority,
//////            userInfo: [.imageIdKey: content.id]
//////        )
//////
//////        return request
//////    }
////}
