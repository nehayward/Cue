//import SwiftUI
//import Kingfisher
//import SonosKit
//import MusicKit
//import MusicSearchKit
//
//struct KFLightArtworkView: View {
//    @Binding var thumbnail: URL?
//    var content: PlayableContent
//    var id: String
//    var contentType: ContentType
//    var showMusicSource: Bool
//    
//    var body: some View {
//        VStack {
//            if let thumbnail {
//                KFImage(source: .network(KF.ImageResource(downloadURL: thumbnail, cacheKey: id)))
//                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 50, height: 50)))
//                    .interpolation(.low)
//                    .cancelOnDisappear(true)
//                    .fade(duration: 0)
//                    .placeholder {
//                        placeholderView
//                    }
//                    .onSuccess { result in
//                        print("Image loaded from cache: \(result.cacheType)")
//                    }
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
//                    .clipShape(contentShape)
//                    .shadow(radius: 2)
//                    .overlay(alignment: .bottomTrailing) {
//                        if showMusicSource {
//                            overlayIcons
//                        }
//                    }
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
//    }
//    
//    @ViewBuilder
//    private var placeholderView: some View {
//        Rectangle()
//            .aspectRatio(contentMode: .fit)
//            .foregroundStyle(.ultraThinMaterial)
//            .shadow(radius: 2)
//            .overlay {
//                if thumbnail == nil {
//                    Image(systemName: "music.note")
//                        .resizable()
//                        .scaledToFit()
//                        .foregroundStyle(.foreground)
//                        .frame(width: 24, height: 24)
//                        .bold()
//                }
//            }
//    }
//    
//    private var contentShape: some Shape {
//        if [.artist, .libraryArtist, .artistRadio].contains(contentType) {
//            return AnyShape(Circle())
//        } else {
//            return AnyShape(RoundedRectangle(cornerRadius: 8))
//        }
//    }
//    
//    @ViewBuilder
//    private var overlayIcons: some View {
//        Group {
//            content.content.service.icon
//                .containerRelativeFrame(.horizontal) { size, _ in
//#if targetEnvironment(macCatalyst)
//                    size * 0.02
//#else
//                    size * 0.025
//#endif
//                }
//                .padding(4)
//                .shadow(radius: 2)
//            
//            if content.content.type == .favorite {
//                Image(systemName: "star.fill")
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
//                    .foregroundStyle(.white.gradient)
//                    .containerRelativeFrame(.horizontal) { size, _ in
//                        size * 0.03
//                    }
//                    .padding(4)
//                    .shadow(radius: 10)
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
