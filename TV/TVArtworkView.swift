import Kingfisher
import SwiftUI
import SonosKit
import MusicSearchKit

struct TVArtworkView: View {
    var group: GroupRoom
    var shouldFade: Bool = false
    var showBadge: Bool = true
    
    @State private var alarmRunning: Bool = false
    @State private var previous: URL?
    @State private var currentImage: UIImage?
    
    var body: some View {
        ZStack {
            KFImage(previous)
                .fade(duration: 0)
                .cacheMemoryOnly()
                .waitForCache()
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            KFImage(group.coordinatorRoom.track.artworkURL)
                .onSuccess { r in
                    if currentImage?.pngData() != r.image.pngData() {
                        currentImage = r.image
                    }
                }
                .placeholder { progress in
                    Image(uiImage: currentImage ?? .init()).resizable()
                }
                .forceTransition(previous != group.coordinatorRoom.track.artworkURL)
                .fade(duration: shouldFade ? 0.3 : 0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 2)
                .overlay(alignment: .bottomTrailing) {
                    TVArtworkBadgeView(group: group, alarmRunning: alarmRunning)
                        .transition(.opacity)
                }
                .overlay {
                    if group.isMuted, showBadge {
                        Image(systemName: "speaker.slash.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.primary)
                            .bold()
                            .containerRelativeFrame(.horizontal) { size, axis in
                                size * 0.1
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .foregroundStyle(.ultraThinMaterial)
                            }
                            .transition(.opacity)
                            .tint(.primary)
                    }
                }
                .overlay {
                    if showBadge, group.coordinatorRoom.track.artworkURL == nil {
                        Rectangle()
                            .foregroundStyle(.ultraThickMaterial)
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
                                }
                                
                                if group.playbackService == .lineIn, showBadge {
                                    Image(systemName: "audio.jack.stereo")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.primary.secondary)
                                        .fontWeight(.light)
                                        .frame(maxWidth: 100)
                                        .tint(Color.primary.secondary)
                                }
                            }
                    }
                }
                .onChange(of: group.coordinatorRoom.track.artworkURL) { old, new in
                    if let old {
                        previous = old
                    }
                }
                .onChange(of: group.rooms.contains(where: \.alarmRunning), initial: true) { old, new in
                    alarmRunning = new
                }
                .animation(.spring, value: group.isMuted)
        }
    }
}
