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

    // Snapshot of `shouldFade` taken when the artwork URL changes — see the
    // `.task` below. The fade must be decided at skip time, not when the
    // (possibly slow) image load lands, otherwise a late load fades in even
    // though the user tapped Next.
    @State private var animateArtworkChange: Bool = false

    var cornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 8 : 16
    }

    fileprivate var imageIDKey: String {
        let track = group.coordinatorRoom.track
        let service = String(describing: track.musicService)
        if !track.album.isEmpty { return "\(track.album).\(service).player" }
        if !track.name.isEmpty  { return "\(track.name).\(service).player" }
        return track.trackID + ".player"
    }

    private var artworkRequest: ImageRequest? {
        guard let url = group.coordinatorRoom.track.artworkURL else { return nil }
        return ImageRequest(
            url: url,
            processors: [.resize(width: 500)],
            priority: .high,
            userInfo: [.imageIdKey: imageIDKey]
        )
    }

    // Synchronous memory-cache lookup used as the fallback below. On a hit
    // the very first paint already shows the artwork — no placeholder flash
    // on Catalyst app re-open — without needing a custom init to seed @State.
    private var cachedImage: UIImage? {
        guard let artworkRequest else { return nil }
        return ImagePipeline.shared.cache.cachedImage(for: artworkRequest)?.image
    }

    // Prefer the loaded image; fall back to the cache so there's no gap
    // before `.task` runs.
    private var displayImage: UIImage? {
        currentImage ?? cachedImage
    }

    var body: some View {
        VStack {
            VStack {
                if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: showBadge ? .fit : .fill)
                        .transition(.opacity)
                        .animation(.smooth(duration: animateArtworkChange ? defaultFadeDuration : 0), value: displayImage)
                } else {
                    Rectangle()
                        .foregroundStyle(.thickMaterial)
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if group.playbackService != .lineIn && group.coordinatorRoom.track.sonosAlbumArtURL == nil && showBadge && displayImage == nil {
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
            // Async load that auto-cancels when the URL changes. SwiftUI
            // discards the in-flight load on id change so a slow request for
            // the previous track can't complete after a fast one for the new
            // track and overwrite `currentImage` with stale art. Initial
            // value comes from `init()`'s synchronous cache lookup, so this
            // only fires for cache misses or URL changes.
            .task(id: group.coordinatorRoom.track.artworkURL) {
                // Decide the fade up front. `shouldFade` is reliably false
                // right after a user skip (LargePlayerView only flips it back
                // true ~200ms later), so snapshotting here means a slow image
                // load can't fade in after the fact.
                animateArtworkChange = shouldFade
                guard let artworkRequest else {
                    currentImage = nil
                    return
                }
                if let cached = ImagePipeline.shared.cache.cachedImage(for: artworkRequest) {
                    currentImage = cached.image
                    return
                }
                do {
                    let image = try await ImagePipeline.shared.image(for: artworkRequest)
                    currentImage = image
                } catch {
                    // Swallow errors silently — the Sonos proxy for Spotify is
                    // unreliable right at track boundaries (the speaker may not
                    // have fetched the new art yet). Keeping the previous image
                    // is better than flashing a grey placeholder.
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
