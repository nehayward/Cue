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
    /// The corner rounding for anything that isn't an artist; the player
    /// asks for the same radius the Sonos artwork gets.
    var cornerRadius: CGFloat = 4
    /// What shows while the image loads (and behind a missing one). Solid
    /// by default, as a row's thumbnail should be; a wall of tiles asks
    /// for something translucent so a page still loading reads as a
    /// texture rather than a slab.
    var placeholderStyle: AnyShapeStyle = AnyShapeStyle(.secondary)
    /// Lets the artwork itself be picked up and dropped on a speaker or a
    /// queue, the way the Sonos player's cover can. Applied to the image
    /// rather than the frame around it, so the drag preview is the cover.
    var isDraggable: Bool = false
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
    
    // `imageID`, not `userInfo[.imageIdKey]`: Nuke 13 stopped reading that key,
    // so passing it there compiles and silently leaves the request keyed on its
    // URL. `imageKey` is what makes the same artwork one cache entry no matter
    // which of the candidate URLs resolved it.
    //
    // The key has to carry the size tier as well as the item, though. A 40pt
    // queue row and the 800pt player ask for the same `imageKey`, so keying on
    // the item alone let the row's already-cached thumbnail satisfy the
    // player's request — the big artwork came back visibly soft.
    private var artworkRequest: ImageRequest {
        Self.artworkRequest(for: content, url: artworkURL, preferredSize: preferredSize)
    }

    /// The request a view `preferredSize` wide makes for `content`'s artwork
    /// at `url`. Static so the Lock Screen card can ask for exactly what the
    /// player did, and be answered from the memory cache.
    static func artworkRequest(for content: PlayableContent, url: URL?, preferredSize: Double) -> ImageRequest {
        var request = ImageRequest(url: url)
        // Whether the view resolved to the full-size `artwork` rather than
        // the thumbnail: part of the cache key.
        let usesFullSizeArtwork = preferredSize != 50 && content.artwork != nil
        request.imageID = usesFullSizeArtwork ? "\(content.imageKey)#full" : content.imageKey
        // Decode no bigger than the view shows. Plex (and Subsonic, and a
        // local folder) hand back the original embedded cover, which is often
        // 1500–3000px — 9 to 36 MB once decoded, for a 50pt row. Nuke's
        // thumbnail path downsamples inside ImageIO, so the full bitmap is
        // never materialized, and the pixel size is part of its cache key,
        // so a row's thumbnail never satisfies the player's request.
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: maxPixelSize(for: preferredSize))
        return request
    }

    /// What the device player's cover asks for (`PlayerView`).
    static let playerPreferredSize: Double = 600

    private static let prefetcher = ImagePrefetcher(destination: .memoryCache)

    /// Decodes `content`'s player cover into the memory cache ahead of time,
    /// in place of whatever was being fetched before.
    static func prefetchPlayerArtwork(for content: PlayableContent) {
        guard let url = content.artwork ?? content.thumbnail else { return }
        prefetcher.stopPrefetching()
        prefetcher.startPrefetching(with: [artworkRequest(for: content, url: url, preferredSize: playerPreferredSize)])
    }

    /// The most pixels worth decoding for a view `points` wide: enough for a
    /// 3x screen, capped so the full-size player doesn't ask for more than
    /// any speaker or service actually serves.
    static func maxPixelSize(for points: Double) -> Float {
        Float(min(points * 3, 1200))
    }
    
    private var placeholder: some View {
        Rectangle()
            .foregroundStyle(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
    
    var body: some View {
        Group {
            if isDraggable {
                artwork.draggable(content)
            } else {
                artwork
            }
        }
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

    /// The image itself, clipped: what gets dragged.
    private var artwork: some View {
        LazyImage(request: artworkRequest) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFit()
                    .onAppear {
                        // Only when someone wants it: the colour is a
                        // 40×40 redraw of the bitmap on the main thread,
                        // and a grid of covers scrolling past was paying
                        // for one per tile to hand the result to nobody.
                        guard let foundAverageColor,
                              let color = state.imageContainer?.image.findAverageColor(cacheKey: content.imageKey) else { return }
                        foundAverageColor(Color(uiColor: color))
                    }
            } else {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(placeholderStyle)
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
        .clipShape(.rect(cornerRadius: isCircular ? preferredSize / 2 : cornerRadius))
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
    
    /// Every station keeps its service's logo, as the Sonos player's cover
    /// does — a Plex or Apple Music station read as "some radio" with the
    /// generic glyph. That glyph is only for a station with no known service.
    private var showsServiceIcon: Bool { !isRadio || service != .unknown }

    /// Large covers (the player's) get the badge the Sonos player's cover
    /// has — 24pt, inset 8 — rather than a row thumbnail's 18pt, which read
    /// as a speck on a cover that size.
    private var isLarge: Bool { size > 100 }

    var body: some View {
        service.icon
            .opacity(showsServiceIcon ? 1 : 0)
            .frame(width: isLarge ? 24 : 18, height: isLarge ? 24 : 18, alignment: .bottomLeading)
            .padding(2)
            .overlay {
                Image(systemName: "radio.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .padding(2)
                    .opacity(showsServiceIcon ? 0 : 1)
            }
            .padding(isLarge ? 6 : 0)
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
