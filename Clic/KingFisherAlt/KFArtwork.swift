//import Kingfisher
//import SwiftUI
//import SonosKit
//import MusicSearchKit
//
//struct KFArtworkView: View {
//    @Environment(AlertService.self) var alertService
//
//    var group: GroupRoom
//    var isDraggable: Bool = false
//    var showBadge: Bool = true
//    var shouldFade: Bool = false
//
//    var fadeDuration: Double {
//        shouldFade ? defaultFadeDuration : 0
//    }
//    
//    @State private var defaultFadeDuration: Double = 0.2
//    @State private var alarmRunning: Bool = false
//    @State private var previous: URL?
//    @State private var currentData: Data?
//    
//    var cornerRadius: CGFloat {
//        UIDevice.current.userInterfaceIdiom == .phone ? 8 : 16
//    }
//
//    var body: some View {
//        ZStack {
//            KFImage(previous)
//                .fade(duration: 0)
//                .cacheMemoryOnly()
//                .waitForCache()
//                .cancelOnDisappear(true)
//                .resizable()
//                .aspectRatio(contentMode: .fit)
//                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
//                .opacity(group.coordinatorRoom.track.artworkURL == nil ? 0 : 1)
//            KFImage(group.coordinatorRoom.track.artworkURL)
//                .onSuccess { r in
//                    if currentData != r.image.pngData() {
//                        defaultFadeDuration = 0.2
//                        currentData = r.image.pngData()
//                    } else {
//                        defaultFadeDuration = 0
//                    }
//                }
//                .cancelOnDisappear(true)
//                .fade(duration: fadeDuration)
//                .resizable()
//                .aspectRatio(contentMode: .fit)
//                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
//                .shadow(radius: 1)
//                .overlay(alignment: .bottomTrailing) {
//                    GeometryReader { proxy in
//                        ArtworkBadgeView(group: group, alarmRunning: alarmRunning, size: proxy.size.width)
//                    }
//                }
//                .if(isDraggable) {
//                    $0.draggable(group.coordinatorRoom.track.toPlayable)
//                }
//                .overlay {
//                    if group.isMuted, showBadge {
//                        GeometryReader { proxy in
//                            Image(systemName: "speaker.slash.fill")
//                                .resizable()
//                                .scaledToFit()
//                                .foregroundStyle(.secondary)
//                                .bold()
//                                .frame(width: proxy.size.width * 0.5)
//                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
//                                .background {
//                                    RoundedRectangle(cornerRadius: cornerRadius)
//                                        .foregroundStyle(.ultraThinMaterial)
//                                }
//                                .transition(.opacity)
//                                .tint(.secondary)
//                        }
//                    }
//                }
//                .animation(.spring, value: group.isMuted)
//                .opacity(group.coordinatorRoom.track.artworkURL == nil ? 0 : 1)
//                .overlay {
//                    if showBadge, group.coordinatorRoom.track.artworkURL == nil {
//                        RoundedRectangle(cornerRadius: cornerRadius)
//                            .foregroundStyle(.ultraThickMaterial)
//                            .aspectRatio(contentMode: .fit)
//                            .overlay {
//                                GeometryReader { proxy in
//                                    if showBadge, group.coordinatorRoom.track.artworkURL == nil, group.playbackService != .lineIn {
//                                        Image(systemName: "music.note")
//                                            .resizable()
//                                            .scaledToFit()
//                                            .foregroundStyle(.secondary)
//                                            .fontWeight(.light)
//                                            .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
//                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
//                                            .tint(.secondary)
//                                            .transition(.opacity)
//                                    }
//                                    
//                                    if showBadge, group.playbackService == .lineIn {
//                                        Image(systemName: "audio.jack.stereo")
//                                            .resizable()
//                                            .scaledToFit()
//                                            .foregroundStyle(.secondary)
//                                            .fontWeight(.light)
//                                            .frame(width: proxy.size.width * 0.5, height: proxy.size.width * 0.5)
//                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
//                                            .tint(.secondary)
//                                            .transition(.opacity)
//                                    }
//                                }
//                            }
//                            .shadow(radius: 1)
//                    }
//                }
//                .onTapGesture(count: 2) {
//                    #if !targetEnvironment(macCatalyst)
//                    if group.coordinatorRoom.track.toPlayable.content.service == .apple {
//                        Task {
//                            HapticManager.shared.fireHaptic(.buttonPress)
//                            alertService.showAlert(with: "Added to Library", imageName: "star.fill")
//                            try await AppleMusicAPI().favoriteSong(songId: group.coordinatorRoom.track.toPlayable.content.id)
//                        }
//                    }
//                    #endif
//                }
//                .onChange(of: group.coordinatorRoom.track.artworkURL) { old, new in
//                    if let old {
//                        previous = old
//                    }
//                }
//                .onChange(of: group.rooms.contains(where: \.alarmRunning), initial: true) { old, new in
//                    alarmRunning = new
//                }
//                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
//        }
////        GeometryReader { proxy in
////            VStack {
////                if let currentImage = artwork.wrappedValue {
////                    Image(uiImage: currentImage)
////                        .resizable()
////                        .aspectRatio(contentMode: .fit)
////                        .transition(.opacity)
////                        .animation(.smooth(duration: viewCount.wrappedValue > 1 ? animation : 0), value: currentImage)
////                } else {
////                    Rectangle()
////                        .foregroundStyle(.thickMaterial)
////                        .aspectRatio(contentMode: .fit)
////                        .overlay {
////                            if group.coordinatorRoom.track.artworkURL == nil, group.playbackService != .lineIn, showBadge {
////                                Image(systemName: "music.note")
////                                    .resizable()
////                                    .scaledToFit()
////                                    .foregroundStyle(.primary.secondary)
////                                    .fontWeight(.light)
////                                    .frame(maxWidth: 100)
////                                    .tint(Color.primary.secondary)
////                                    .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
////                            }
////
////                            if group.playbackService == .lineIn, showBadge {
////                                Image(systemName: "audio.jack.stereo")
////                                    .resizable()
////                                    .scaledToFit()
////                                    .foregroundStyle(.primary.secondary)
////                                    .fontWeight(.light)
////                                    .frame(maxWidth: 100)
////                                    .tint(Color.primary.secondary)
////                                    .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
////                            }
////                        }
////                }
////            }
////            #if DEBUG && SCREENSHOT
////            .overlay {
////                Rectangle()
////                    .foregroundStyle(.ultraThinMaterial)
////            }
////            #endif
////            .clipShape(RoundedRectangle(cornerRadius: 8))
////            .shadow(radius: 2)
////            .overlay(alignment: .bottomTrailing) {
////                ArtworkBadgeView(group: $group, size: proxy.size.width, alarmRunning: $alarmRunning)
////            }
////            .if(isDraggable) {
////                $0.draggable(group.coordinatorRoom.track.toPlayable)
////            }
////            .overlay {
////                if group.isMuted, showBadge {
////                    Image(systemName: "speaker.slash.fill")
////                        .resizable()
////                        .scaledToFit()
////                        .foregroundStyle(.primary)
////                        .bold()
////                        .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
////                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
////                        .background {
////                            RoundedRectangle(cornerRadius: 8)
////                                .foregroundStyle(.ultraThinMaterial)
////                        }
////                        .transition(.opacity)
////                        .tint(.primary)
////                }
////            }
////            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
////            .onChange(of: group.rooms.contains(where: \.alarmRunning), initial: true) { old, new in
////                alarmRunning = new
////            }
////            .onChange(of: group.coordinatorRoom.track.artworkURL) { _, newURL in
////                if useExternal { return }
////                // Simply call loadArtwork - cancellation is handled in property observer
////                imageTask = loadArtwork(url: newURL)
////            }
////            .onTapGesture(count: 2) {
////#if !targetEnvironment(macCatalyst)
////                if group.coordinatorRoom.track.toPlayable.content.service == .apple {
////                    Task {
////                        HapticManager.shared.fireHaptic(.buttonPress)
////                        alertService.showAlert(with: "Added to Library", imageName: "star.fill")
////                        try await AppleMusicAPI().favoriteSong(songId: group.coordinatorRoom.track.toPlayable.content.id)
////                    }
////                }
////#endif
////            }
////            .onAppear {
////                imageTask = loadArtwork(url: group.coordinatorRoom.track.artworkURL)
////                internalCount = 0
////            }
////            .onDisappear {
////                imageTask?.cancel()
////                imageTask = nil
////            }
////            .animation(.spring, value: group.isMuted)
////        }
//    }
//    
////    private func loadArtwork(url: URL?) -> ImageTask? {
////        if useExternal { return nil }
////        guard let url else {
////            Task { @MainActor in
////                artwork.wrappedValue = nil
////            }
////            return nil
////        }
////
////        let imageRequest = ImageRequest(url: url, priority: .high)
////        return ImagePipeline.shared.loadImage(with: imageRequest) { result in
////            Task { @MainActor in
////                switch result {
////                case .success(let response):
////                    if !Task.isCancelled {
////                        if self.artwork.wrappedValue?.pngData() == response.image.pngData() {
////                            viewCount.wrappedValue = 0
////                        }
////                        artwork.wrappedValue = response.image
////                        viewCount.wrappedValue += 1
////                    }
////                case .failure:
////                    if !Task.isCancelled {
////                        artwork.wrappedValue = nil
////                    }
////                }
////                // Set imageTask to nil after completion
////                imageTask = nil
////            }
////        }
////    }
//}
//
////
////#Preview("Empty") {
////    ArtworkView(track: .constant(Track(trackID: "", name: "", TVMode: false)))
////        .environment(SonosService.shared)
////}
////
////#Preview("Dua Lipa") {
////    ArtworkView(track: .constant(Track(trackID: "6wf7Yu7cxBSPrRlWeSeK0Q", musicService: .spotify)))
////        .environment(SonosService.shared)
////}
////
////#Preview("White Background") {
////    ArtworkView(track: .constant(Track(trackID: "204669559", musicService: .apple)))
////        .environment(SonosService.shared)
////
////}
////
////#Preview("Dark Album") {
////    ArtworkView(track: .constant(Track(trackID: "7sjuNUjWtSqhbxJ3RAUffm", musicService: .spotify)))
////        .environment(SonosService.shared)
////}
////
