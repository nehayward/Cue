import Nuke
import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct ArtworkView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService
    
    var isDraggable: Bool = false
    var useExternal: Bool = false
    var image: Binding<UIImage?>? = nil
    var count: Binding<Int>? = nil
    var animation: TimeInterval = 0.2
    var showBadge: Bool = true

    @Binding var group: GroupRoom
    @State private var alarmRunning: Bool = false
    
    // Add task cancellation
    @State private var imageTask: ImageTask? = nil {
        willSet {
            // Cancel previous task before assigning new one
            imageTask?.cancel()
        }
    }
    
    // Internal state as fallback
    @State private var internalImage: UIImage?
    @State private var internalCount: Int = 0
    
    // Computed properties to handle optional bindings
    private var artwork: Binding<UIImage?> {
        image ?? $internalImage
    }
    
    private var viewCount: Binding<Int> {
        count ?? $internalCount
    }

    var body: some View {
        GeometryReader { proxy in
            VStack {
                if let currentImage = artwork.wrappedValue {
                    Image(uiImage: currentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                        .animation(.smooth(duration: viewCount.wrappedValue > 1 ? animation : 0), value: currentImage)
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
                        .transition(.opacity)
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
                ArtworkBadgeView(group: $group, size: proxy.size.width, alarmRunning: $alarmRunning)
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
                if useExternal { return }
                // Simply call loadArtwork - cancellation is handled in property observer
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
                imageTask = loadArtwork(url: group.coordinatorRoom.track.artworkURL)
                internalCount = 0
            }
            .onDisappear {
                imageTask?.cancel()
                imageTask = nil
            }
            .animation(.spring, value: group.isMuted)
        }
    }
    
    private func loadArtwork(url: URL?) -> ImageTask? {
        if useExternal { return nil }
        guard let url else {
            Task { @MainActor in
                artwork.wrappedValue = nil
            }
            return nil
        }
        
        let imageRequest = ImageRequest(url: url, priority: .high)
        return ImagePipeline.shared.loadImage(with: imageRequest) { result in
            Task { @MainActor in
                switch result {
                case .success(let response):
                    if !Task.isCancelled {
                        artwork.wrappedValue = response.image
                        viewCount.wrappedValue += 1
                    }
                case .failure:
                    if !Task.isCancelled {
                        artwork.wrappedValue = nil
                    }
                }
                // Set imageTask to nil after completion
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
