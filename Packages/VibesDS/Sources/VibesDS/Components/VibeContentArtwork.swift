import MusicKit
import MusicSearchKit
import Nuke
import NukeUI
import SonosKit
import SwiftUI

public struct VibeContentArtworkView: View {
    @Environment(SonosService.self) private var sonosService
    
    public var content: PlayableContent
    public var showMusicSource: Bool = true
    var preferredSize: Int = 100
    
    @State private var imageRequest: ImageRequest?
    @State private var overlaySize: CGFloat = 20 // Default size for the overlay icon
    @State private var width: CGFloat = 100 // Default padding

    public init(content: PlayableContent, showMusicSource: Bool = true) {
        self.content = content
        self.showMusicSource = showMusicSource
    }
    
    public var body: some View {
        LazyImage(request: imageRequest) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .bottomTrailing) {
                        showMusicSource ? musicSourceOverlay : nil
                    }
            } else {
                placeholderView(error: state.error)
            }
        }
        .transition(.opacity)
        .id(content.id)
        .clipShape(contentShape)
        .shadow(radius: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        width = proxy.size.width
                        calculateOverlaySize(from: proxy.size)
                    }
            }
        )
        .task(id: content.id) {
            await loadImage()
        }
    }
    
    // MARK: - Placeholder View
    @ViewBuilder
    private func placeholderView(error: Error?) -> some View {
        Rectangle()
            .foregroundStyle(.ultraThinMaterial)
            .overlay {
                if error != nil {
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .bold()
                        .foregroundStyle(.secondary)
                }
            }
    }
    
    // MARK: - Content Shape
    private var contentShape: AnyShape {
        [.artist, .libraryArtist].contains(content.content.type)
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Music Source Overlay
    private var musicSourceOverlay: some View {
        content.content.service.icon
            .frame(width: overlaySize, height: overlaySize, alignment: .bottomTrailing)
            .shadow(radius: 2)
            .padding(4)
            .foregroundStyle(.white)
    }
    
    // MARK: - Calculate Overlay Size
    private func calculateOverlaySize(from size: CGSize) {
        overlaySize = min(size.width * 0.2, 44)
    }
    
    // MARK: - Load Image
    private func loadImage() async {
        guard !content.id.isEmpty else {
            imageRequest = nil
            return
        }
        
        if let cachedURL = try? cachedArtworkURL(for: content.id) {
            imageRequest = makeImageRequest(url: cachedURL)
            return
        }
        
        if let url = content.artwork, !url.absoluteString.contains("get") {
            imageRequest = makeImageRequest(url: url)
            return
        }
        
        guard let artworkURL = await sonosService.getArtwork(from: content, size: preferredSize) else {
            imageRequest = makeImageRequest(url: content.artwork)
            return
        }
        
        imageRequest = makeImageRequest(url: artworkURL)
    }
    
    private func cachedArtworkURL(for id: String) throws -> URL? {
        let dataCache = try DataCache(name: "com.cue.imageCache")
        if dataCache.containsData(for: id),
           ![.playlist, .libraryPlaylist].contains(content.content.type) {
            return URL(string: id) // Assuming cached URL logic
        }
        return nil
    }
    
    // MARK: - Create Image Request
    private func makeImageRequest(url: URL?, priority: ImageRequest.Priority = .veryHigh) -> ImageRequest {
        var request = ImageRequest(url: url, priority: priority)
        // `imageID`, not `userInfo[.imageIdKey]`: Nuke 13 stopped reading that
        // key, so passing it there compiles and silently keys each request on
        // its URL — defeating the one-entry-per-`content.id` design this view
        // is built around, since it tries several candidate URLs for the same
        // artwork.
        request.imageID = content.id
        return request
    }
}
#Preview("Dua Lipa") {
    VibeContentArtworkView(
        content: .init(
        title: "Radical Optimism",
        subtitle: "Dua Lipa",
        thumbnail: nil,
        artwork: URL(
            string: "https://i.scdn.co/image/ab67616d00001e02361debc2873b3aa493304b6d"
        ),
        content: .init(
            service: .spotify,
            id: "1Mo92916G2mmG7ajpmSVrc",
            type: .album,
            location: nil
        )
        )
    )
    .environment(SonosService.shared)
    
}



//#Preview("Empty") {
//    ContentArtworkView(track: .constant(Track(trackID: "", name: "", TVMode: false)))
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
