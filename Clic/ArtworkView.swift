import Nuke
import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct ArtworkView: View {
    @Environment(AlertService.self) var alertService
    
    let group: GroupRoom
    var isDraggable: Bool = false
    var showBadge: Bool = true
    var shouldFade: Bool = false
    
    @State private var defaultFadeDuration: Double = 0.3
    @State private var alarmRunning: Bool = false
    @State private var currentImage: UIImage?
    
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
        if !group.coordinatorRoom.track.album.isEmpty {
            let album = group.coordinatorRoom.track.album
            let artist = group.coordinatorRoom.track.artist
            return [album, artist, suffix].compactMap { $0 }.joined(separator: ".")
        }
        
        if !group.coordinatorRoom.track.name.isEmpty {
            let track = group.coordinatorRoom.track.name
            let artist = group.coordinatorRoom.track.artist
            return [track, artist, suffix].compactMap { $0 }.joined(separator: ".")
        }
        
        return group.coordinatorRoom.track.trackID + suffix
    }

    var body: some View {
        VStack {
            VStack {
                if let currentImage = currentImage {
                    Image(uiImage: currentImage)
                        .resizable()
                        .aspectRatio(contentMode: showBadge ? .fit : .fill)
                        .transition(.opacity)
                        .animation(.smooth(duration: shouldFade ? defaultFadeDuration : 0), value: currentImage)
                } else {
                    Rectangle()
                        .foregroundStyle(.thickMaterial)
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if group.playbackService != .lineIn && group.coordinatorRoom.track.sonosAlbumArtURL == nil && showBadge && currentImage == nil {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                                    .fontWeight(.light)
                                    .scaleEffect(0.5)
                                    .tint(Color.primary.gradient)
                            }
                            if group.playbackService == .lineIn, showBadge {
                                Image(systemName: "audio.jack.stereo")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.primary)
                                    .fontWeight(.light)
                                    .scaleEffect(0.5)
                                    .tint(Color.primary.gradient)
                            }
                        }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                ArtworkBadgeView(group: group, alarmRunning: alarmRunning)
                    .opacity(showBadge ? 1 : 0 )
                    .contentTransition(.identity)
            }
            #if DEBUG && SCREENSHOT
            .overlay {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
            }
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
            .if(isDraggable) {
                $0.draggable(group.coordinatorRoom.track.toPlayable)
            }
            .overlay {
                if group.isMuted, showBadge {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        Task {
                            await SonosService.shared.setGroupMute(group: group, mute: false)
                            withAnimation {
                                group.isMuted.toggle()
                            }
                        }
                    } label: {
                        Image(systemName: "speaker.slash.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.primary)
                            .bold()
                            .scaleEffect(0.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .foregroundStyle(.ultraThinMaterial)
                            }
                            .tint(.primary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onChange(of: group.rooms.contains(where: \.alarmRunning), initial: true) { old, new in
                alarmRunning = new
            }
            .onChange(of: group.coordinatorRoom.track.artworkURL) { old, newURL in
                if old == newURL { return }
                imageTask?.cancel()
                imageTask = loadArtwork(url: newURL, imageID: imageIDKey)
            }
            .onAppear {
                // Try to restore from cache first
                let request = ImageRequest(url: group.coordinatorRoom.track.artworkURL,
                                           processors: [.resize(width: 500)],
                                           priority: .high,
                                           userInfo: [.imageIdKey: imageIDKey])
                if let image = ImagePipeline.shared.cache.cachedImage(for: request) {
                    currentImage = image.image
                }
                
                // Always ensure we have a load task if currentImage is nil
                if currentImage == nil {
                    imageTask = loadArtwork(url: group.coordinatorRoom.track.artworkURL, imageID: imageIDKey)
                }
            }
            .onDisappear {
                imageTask?.cancel()
                imageTask = nil
            }
        }
    }
    
    nonisolated private func loadArtwork(url: URL?, imageID: String) -> ImageTask? {
        guard let url else {
            Task { @MainActor in
                currentImage = nil
            }
            return nil
        }
        
        let imageRequest = ImageRequest(url: url,
                                        processors: [.resize(width: 500)],
                                        priority: .high,
                                        userInfo: [.imageIdKey: imageID])
        
        return ImagePipeline.shared.loadImage(with: imageRequest) { result in
            Task { @MainActor in
                switch result {
                case .success(let response):
                    self.currentImage = response.image
                default:
                    currentImage = nil
                    break
                }
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
