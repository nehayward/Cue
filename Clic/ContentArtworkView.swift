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
    
    @State private var fetchedArtworkURL: URL?
    @State private var isLoadingArtwork = false
    
    fileprivate var imageIDKey: String {
        if let albumID = content.metadata?.album, !albumID.isEmpty {
            let artist = content.metadata?.artist
            return [albumID, artist, preferredSize.description].compactMap { $0 }.joined(separator: ".")
        }
        return content.id
    }
    
    private var artworkURL: URL? {
        if preferredSize != 50, let artwork = content.artwork {
            return artwork
        }
        // First try the original thumbnail
        if let thumbnail = content.thumbnail {
            return thumbnail
        }
        
        // If no thumbnail and this is a library artist, try the fetched artwork
        if content.content.type == .artist, content.content.service == .library {
            return fetchedArtworkURL
        }
        
        return nil
    }

    var body: some View {
        LazyImage(request: ImageRequest(url: artworkURL, userInfo: [.imageIdKey: imageIDKey, .thumbnailKey: preferredSize == 50])) { state in
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
        .id(fetchedArtworkURL)
        #if DEBUG && SCREENSHOT
        .overlay {
            Rectangle()
                .foregroundStyle(.ultraThinMaterial)
        }
        #endif
        .clipShape(contentShape)
        .overlay(alignment: .bottomTrailing) {
            if showMusicSource {
                OverlayIcons(content: content)
            }
            if isLoadingArtwork {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .task {
            if content.content.type == .artist, content.content.service == .library {
                if ImagePipeline.shared.cache.containsCachedImage(for: ImageRequest(url: content.thumbnail, userInfo: [.imageIdKey: imageIDKey, .thumbnailKey: preferredSize == 50])) {
                    return
                }
                await fetchArtworkIfNeeded()
            }
        }
    }
    
    private var contentShape: some Shape {
        if [.artist, .libraryArtist, .artistRadio].contains(content.content.type) {
            return AnyShape(Circle())
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 4))
        }
    }
    
    private func fetchArtworkIfNeeded() async {
        guard fetchedArtworkURL == nil, content.thumbnail == nil else {
            return
        }
        
        isLoadingArtwork = true
        let artworkURL = await MusicSearchService.shared.appleLibraryArtistArtwork(name: content.title)
        fetchedArtworkURL = artworkURL
        isLoadingArtwork = false
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
