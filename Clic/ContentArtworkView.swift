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
    var foundAverageColor: ((Color) -> Void)? = nil
    
    @State private var fetchedArtworkURL: URL?

    private var isCircular: Bool {
        content.content.type.isArtist || content.content.type == .artistRadio
    }
    
    private var needsArtworkFetch: Bool {
        content.thumbnail == nil && content.content.type.isArtist &&
        (content.content.service == .library || content.content.service == .apple)
    }
    
    private var artworkURL: URL? {
        if preferredSize != 50, let artwork = content.artwork {
            return artwork
        }
        if let thumbnail = content.thumbnail {
            return thumbnail
        }
        return fetchedArtworkURL
    }
    
    private static let targetSize = CGSize(width: 150, height: 150) // 50pt * 3x scale
    
    private var placeholder: some View {
        Rectangle()
            .foregroundStyle(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
    
    var body: some View {
        LazyImage(request: ImageRequest(url: artworkURL, userInfo: [.imageIdKey: content.imageKey])) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFit()
                    .onAppear {
                        guard let color = state.imageContainer?.image.findAverageColor(cacheKey: content.imageKey) else { return }
                        let averageColor = Color(uiColor: color)
                        foundAverageColor?(averageColor)
                    }
            } else {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
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
        .clipShape(.rect(cornerRadius: isCircular ? preferredSize / 2 : 4))
        .overlay(alignment: .bottomTrailing) {
            OverlayIcons(content: content, service: content.content.service, isRadio: content.content.type.isRadio, size: preferredSize)
                .opacity(showMusicSource ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            guard let foundAverageColor,
                  let cached = UIImage.cachedAverageColor(forKey: content.imageKey) else { return }
            foundAverageColor(Color(uiColor: cached))
        }
        .task(id: content.id) {
            guard needsArtworkFetch, fetchedArtworkURL == nil else { return }
            fetchedArtworkURL = await MusicSearchService.shared.appleLibraryArtistArtwork(name: content.title)
        }
    }
}

fileprivate struct PlaceHolderView: View {
    var body: some View {
        Rectangle()
            .foregroundStyle(.tertiary)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}

fileprivate struct OverlayIcons: View {
    var content: PlayableContent
    let service: MusicService
    let isRadio: Bool
    let size: Double
    
    private var showsServiceIcon: Bool { !isRadio || service.hasBrandedRadioBadge }

    var body: some View {
        service.icon
            .opacity(showsServiceIcon ? 1 : 0)
            .frame(width: 18, height: 18, alignment: .bottomLeading)
            .padding(2)
            .overlay {
                Image(systemName: "radio.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .padding(2)
                    .opacity(showsServiceIcon ? 0 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .foregroundStyle(content.content.type.isArtist ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
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
