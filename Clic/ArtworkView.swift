import Nuke
import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct ArtworkView: View {
    @Environment(AlertService.self) var alertService
    
    var group: GroupRoom
    var isDraggable: Bool = false
    var showBadge: Bool = true
    var shouldFade: Bool = false
    
    @State private var defaultFadeDuration: Double = 0.3
    @State private var alarmRunning: Bool = false
    @State private var currentImage: UIImage?
    @State private var currentImageHash: Int? // Lightweight hash for comparison
    
    @State private var imageTask: ImageTask? = nil {
        willSet {
            imageTask?.cancel()
        }
    }
    
    var cornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 8 : 16
    }
    
    fileprivate var imageIDKey: String {
        let suffix = "player"
        if let albumID = group.coordinatorRoom.track.toPlayable.metadata?.album, !albumID.isEmpty {
            let artist = group.coordinatorRoom.track.toPlayable.metadata?.artist
            return [albumID, artist, suffix].compactMap { $0 }.joined(separator: ".")
        }
        return group.coordinatorRoom.track.trackID + suffix
    }

    var body: some View {
        GeometryReader { proxy in
            VStack {
                if let currentImage = currentImage {
                    Image(uiImage: currentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                        .animation(.smooth(duration: shouldFade ? defaultFadeDuration : 0), value: currentImage)
                } else {
                    Rectangle()
                        .foregroundStyle(.thickMaterial)
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if group.playbackService != .lineIn && group.coordinatorRoom.track.sonosAlbumArtURL == nil || showBadge || currentImage == nil {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                                    .fontWeight(.light)
                                    .frame(maxWidth: 100)
                                    .tint(Color.primary.secondary)
                                    .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
                            }
                            if group.playbackService == .lineIn, showBadge {
                                Image(systemName: "audio.jack.stereo")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.primary.secondary)
                                    .fontWeight(.light)
                                    .frame(maxWidth: 100)
                                    .tint(Color.primary.secondary)
                                    .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
                            }
                        }
                }
            }
            #if DEBUG && SCREENSHOT
            .overlay {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
            }
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
            .overlay(alignment: .bottomTrailing) {
                GeometryReader { proxy in
                    ArtworkBadgeView(group: group, alarmRunning: alarmRunning, size: proxy.size.width)
                }
            }
            .if(isDraggable) {
                $0.draggable(group.coordinatorRoom.track.toPlayable)
            }
            .overlay {
                if group.isMuted, showBadge {
                    Image(systemName: "speaker.slash.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.primary)
                        .bold()
                        .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .foregroundStyle(.ultraThinMaterial)
                        }
                        .transition(.opacity)
                        .tint(.primary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onChange(of: group.rooms.contains(where: \.alarmRunning), initial: true) { old, new in
                alarmRunning = new
            }
            .onChange(of: group.coordinatorRoom.track.artworkURL) { old, newURL in
                if old == newURL { return }
                imageTask?.cancel()
                imageTask = loadArtwork(url: newURL)
            }
            .onAppear {
                let request = ImageRequest(url: group.coordinatorRoom.track.artworkURL,
                                           processors: [.resize(width: 500)],
                                           priority: .high,
                                           userInfo: [.imageIdKey: imageIDKey])
                if let image = ImagePipeline.shared.cache.cachedImage(for: request), currentImage != image.image {
                    currentImage = image.image
                    currentImageHash = image.image.lightweightHash()
                } else {
                    imageTask = loadArtwork(url: group.coordinatorRoom.track.artworkURL)
                }
            }
            .onDisappear {
                imageTask?.cancel()
                imageTask = nil
            }
        }
    }
    
    nonisolated private func loadArtwork(url: URL?) -> ImageTask? {
        guard let url else {
            Task { @MainActor in
                currentImage = nil
                currentImageHash = nil
            }
            return nil
        }
        
        let imageRequest = ImageRequest(url: url,
                                        processors: [.resize(width: 500)],
                                        priority: .high,
                                        userInfo: [.imageIdKey: imageIDKey])
        return ImagePipeline.shared.loadImage(with: imageRequest) { result in
            Task { @MainActor in
                switch result {
                case .success(let response):
                    // Efficient image comparison: object identity -> properties -> lightweight hash
                    if self.imageTask != nil, !self.isSameImage(response.image) {
                        self.currentImage = response.image
                        self.currentImageHash = response.image.lightweightHash()
                    }
                default:
                    currentImage = nil
                    currentImageHash = nil
                    break
                }
            }
        }
    }
    
    // MARK: - Efficient Image Comparison
    private func isSameImage(_ newImage: UIImage) -> Bool {
        guard let currentImage = currentImage else { return false }
        
        // 1. Fast object identity check (same instance)
        if currentImage === newImage { return true }
        
        // 2. Quick property comparison (different images will likely differ here)
        if currentImage.size != newImage.size ||
           currentImage.scale != newImage.scale {
            return false
        }
        
        // 3. Lightweight hash comparison (much faster than pngData)
        let newHash = newImage.lightweightHash()
        return currentImageHash == newHash
    }
}

// MARK: - UIImage Extension for Efficient Comparison
extension UIImage {
    /// Creates a lightweight hash for image comparison - much faster than pngData()
    func lightweightHash() -> Int {
        var hasher = Hasher()
        
        // Hash basic properties
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(scale)
        
        // Sample a few pixels for content comparison (much faster than full data)
        if let cgImage = self.cgImage {
            hasher.combine(cgImage.width)
            hasher.combine(cgImage.height)
            hasher.combine(cgImage.bitsPerComponent)
            hasher.combine(cgImage.bitsPerPixel)
            
            // For additional uniqueness, we could sample corner pixels
            // This is still much faster than converting the entire image
            if let dataProvider = cgImage.dataProvider,
               let data = dataProvider.data {
                let bytes = CFDataGetBytePtr(data)
                let length = CFDataGetLength(data)
                
                // Sample first few bytes and last few bytes for a lightweight signature
                if length > 0 {
                    hasher.combine(bytes?[0] ?? 0)
                    if length > 10 {
                        hasher.combine(bytes?[10] ?? 0)
                        hasher.combine(bytes?[length - 1] ?? 0)
                    }
                }
            }
        }
        
        return hasher.finalize()
    }
}

//
//#Preview("Empty") {
//    ArtworkView(track: .constant(Track(trackID: "", name: "", TVMode: false)))
//        .environment(SonosService.shared)
//}
//
//#Preview("Dua Lipa") {
//    ArtworkView(track: .constant(Track(trackID: "6wf7Yu7cxBSPrRlWeSeK0Q", musicService: .spotify)))
//        .environment(SonosService.shared)
//}
//
//#Preview("White Background") {
//    ArtworkView(track: .constant(Track(trackID: "204669559", musicService: .apple)))
//        .environment(SonosService.shared)
//
//}
//
//#Preview("Dark Album") {
//    ArtworkView(track: .constant(Track(trackID: "7sjuNUjWtSqhbxJ3RAUffm", musicService: .spotify)))
//        .environment(SonosService.shared)
//}
//
