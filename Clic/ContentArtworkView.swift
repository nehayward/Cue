import Nuke
import NukeUI
import SwiftUI
import SonosKit
import MusicKit
import MusicSearchKit

struct ContentArtworkView: View {
    var content: PlayableContent
    var showMusicSource: Bool = true
    var preferredSize: Double = 50.0
    
    fileprivate var imageIDKey: String {
        if let albumID = content.metadata?.album, !albumID.isEmpty {
            return albumID
        }
        return content.id
    }
    
    var body: some View {
        LazyImage(request: ImageRequest(url: content.thumbnail, processors: [.resize(width: preferredSize)], userInfo: [.imageIdKey: imageIDKey])) { state in
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
        .clipShape(contentShape)
        .overlay(alignment: .bottomTrailing) {
            if showMusicSource {
                OverlayIcons(content: content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    private var contentShape: some Shape {
        if [.artist, .libraryArtist, .artistRadio].contains(content.content.type) {
            return AnyShape(Circle())
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

fileprivate struct OverlayIcons: View {
    let content: PlayableContent  // Replace with your actual content type

    var body: some View {
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
