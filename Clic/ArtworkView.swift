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
    
    @Binding var group: GroupRoom
    @State private var alarmRunning: Bool = false
    
    // Add task cancellation
    @State private var imageTask: ImageTask?
    
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
            Group {
                if let currentImage = artwork.wrappedValue {
                    Image(uiImage: currentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else {
                    Rectangle()
                        .foregroundStyle(.thickMaterial)
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if group.coordinatorRoom.track.artworkURL == nil {
                                Image(systemName: "music.note")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onChange(of: group.rooms.contains(where: \.alarmRunning), initial: true) { old, new in
                alarmRunning = new
            }
            .onChange(of: group.coordinatorRoom.track.artworkURL, initial: true) { _, newURL in
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
            .animation(internalCount > 1 ? .smooth(duration: animation) : nil, value: internalImage)
            .onDisappear {
                imageTask?.cancel()
            }
        }
    }
    
    private func loadArtwork(url: URL?) -> ImageTask? {
        guard let url else {
            Task { @MainActor in
                artwork.wrappedValue = nil
            }
            return nil
        }
        
        if Task.isCancelled {
            return nil
        }
        
        let imageRequest = ImageRequest(url: url, priority: .high)
        let task = ImagePipeline.shared.loadImage(with: imageRequest) { result in
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
            }
        }
        
        return task
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
