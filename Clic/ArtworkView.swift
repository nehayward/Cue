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
    
    // Add task cancellation
    @State private var imageTask: ImageTask? = nil {
        willSet {
            // Cancel previous task before assigning new one
            imageTask?.cancel()
        }
    }
    
    var cornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 8 : 16
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
                            if group.coordinatorRoom.track.artworkURL == nil, group.playbackService != .lineIn, showBadge {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.primary.secondary)
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
            .onChange(of: group.coordinatorRoom.track.artworkURL) { _, newURL in
                // Simply call loadArtwork - cancellation is handled in property observer
                imageTask?.cancel()
                imageTask = loadArtwork(url: newURL)
            }
            .onTapGesture(count: 2) {
#if !targetEnvironment(macCatalyst)
                if group.coordinatorRoom.track.toPlayable.content.service == .apple {
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        alertService.showAlert(with: "Added to Library", imageName: "star.fill")
                        try await AppleMusicAPI().favoriteSong(songId: group.coordinatorRoom.track.toPlayable.content.id)
                    }
                }
#endif
            }
            .onAppear {
                let request = ImageRequest(url: group.coordinatorRoom.track.artworkURL)
                if let image = ImagePipeline.shared.cache[request] {
                    currentImage = image.image
                } else {
                    imageTask = loadArtwork(url: group.coordinatorRoom.track.artworkURL)
                }
            }
            .onDisappear {
                imageTask?.cancel()
                imageTask = nil
            }
            .animation(.spring, value: group.isMuted)
        }
    }
    
    
    nonisolated private func loadArtwork(url: URL?) -> ImageTask? {
        guard let url else {
            Task { @MainActor in
                currentImage = nil
            }
            return nil
        }
        
        let imageRequest = ImageRequest(url: url, priority: .high)
        return ImagePipeline.shared.loadImage(with: imageRequest) { result in
            Task { @MainActor in
                switch result {
                case .success(let response):
                    if !Task.isCancelled {
                        currentImage = response.image
                    }
                case .failure:
                    if !Task.isCancelled {
                        currentImage = nil
                    }
                }
                imageTask = nil
            }
        }
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
