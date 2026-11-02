import NukeUI
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
            LazyImage(url: previous) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            LazyImage(url: group.coordinatorRoom.track.artworkURL, transaction: Transaction(animation: shouldFade ? .easeInOut(duration: 0.3) : nil)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let currentImage {
                    Image(uiImage: currentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
                .onCompletion { result in
                    if case .success(let response) = result {
                        currentImage = response.image
                    }
                }
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
