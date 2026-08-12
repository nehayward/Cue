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
    // Renders just the artwork — no badge, rounded-corner clip, shadow, or
    // alarm tracking. For the full-screen blurred background copies of the
    // player, where those decorations are invisible under the blur but still
    // cost render time on every frame of a crossfade.
    var isBackground: Bool = false

    private let defaultFadeDuration: Double = 0.3
    @State private var alarmRunning: Bool = false
    @State private var currentImage: UIImage?
    /// `imageIDKey` of whatever `currentImage` is showing — the cover's identity
    /// rather than the URL it happened to arrive from. See `setImage`.
    @State private var currentImageKey: String?

    var cornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 8 : 16
    }

    fileprivate var imageIDKey: String {
        let track = group.coordinatorRoom.track
        let service = String(describing: track.musicService)
        if !track.album.isEmpty { return "\(track.album).\(service).player" }
        if !track.name.isEmpty  { return "\(track.name).\(service).player" }
        if !track.trackID.isEmpty { return track.trackID + ".player" }
        // Identity-less track (an idle radio player's resting track has no
        // album/name/trackID): key by the artwork URL. A bare ".player" key
        // was shared by every idle radio room, so each room's player showed
        // whichever station's art happened to be cached first.
        return (track.artworkURL?.absoluteString ?? "") + ".player"
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
            decoratedArtwork
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
                    let fade = shouldFade
                    let surface = isBackground ? "bg" : "fg"
                    print("[art] \(surface) task url=\(briefURL(group.coordinatorRoom.track.artworkURL)) key=\(imageIDKey) fade=\(fade)")
                    guard let artworkRequest else {
                        // Hold the outgoing image while a track change is still
                        // in flight. Sonos reports the new item before it has
                        // fetched that item's art, so `artworkURL` is briefly
                        // nil — clearing here drops to the placeholder and back,
                        // which reads as a fade to black rather than a
                        // crossfade. A genuinely empty track (stopped, idle,
                        // TV) has no artwork to hold and still clears.
                        if group.coordinatorRoom.track.isEmpty {
                            print("[art] \(surface) no url, track empty — clearing")
                            setImage(nil, fade: fade)
                        } else {
                            print("[art] \(surface) no url yet — holding previous image")
                        }
                        return
                    }
                    if let cached = ImagePipeline.shared.cache.cachedImage(for: artworkRequest) {
                        print("[art] \(surface) cache hit")
                        setImage(cached.image, fade: fade)
                        return
                    }
                    do {
                        print("[art] \(surface) loading…")
                        let image = try await ImagePipeline.shared.image(for: artworkRequest)
                        print("[art] \(surface) loaded")
                        setImage(image, fade: fade)
                    } catch {
                        print("[art] \(surface) load failed: \(error.localizedDescription)")
                        // Swallow errors silently — the Sonos proxy for Spotify is
                        // unreliable right at track boundaries (the speaker may not
                        // have fetched the new art yet). Keeping the previous image
                        // is better than flashing a grey placeholder.
                    }
                }
        }
    }

    // Base image stack shared by the foreground player artwork and the
    // blurred background copies. ZStack so that during a crossfade the
    // outgoing and incoming artwork overlap in place instead of stacking.
    // The fade is a plain identity-swap opacity transition, animated only
    // by the explicit transaction in `setImage` — there is deliberately no
    // persistent `.animation(value:)` here. Keying an implicit animation on
    // the UIImage instance made every back-to-back load at track boundaries
    // (Sonos proxy URL, then CDN URL) restart and interrupt the fade, and
    // let it animate layout of the full-screen blurred background copies of
    // this view — the stutter that motivated this rewrite.
    private var artworkStack: some View {
        ZStack {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: showBadge ? .fit : .fill)
                    .id(displayImage)
                    .transition(.opacity)
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
        #if DEBUG && SCREENSHOT
        .overlay {
            Rectangle()
                .foregroundStyle(.ultraThinMaterial)
        }
        #endif
    }

    // The badge, rounded-corner clip, shadow, and alarm tracking are
    // invisible under the background blur but still cost render time on
    // every frame of a crossfade, so background copies render the bare
    // artwork stack.
    @ViewBuilder
    private var decoratedArtwork: some View {
        if isBackground {
            artworkStack
        } else {
            let decorated = artworkStack
                .overlay(alignment: .bottomTrailing) {
                    ArtworkBadgeView(group: group, alarmRunning: alarmRunning)
                        .opacity(showBadge ? 1 : 0)
                        .contentTransition(.identity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
                .onChange(of: group.rooms.contains(where: \.alarmRunning), initial: true) { old, new in
                    alarmRunning = new
                }
            if isDraggable {
                decorated.draggable(group.coordinatorRoom.track.toPlayable)
            } else {
                decorated
            }
        }
    }

    // The only place an artwork swap is animated. Scoping the animation to
    // this one transaction (instead of a persistent `.animation` modifier)
    // means unrelated body re-evaluations — playback ticks, mute toggles,
    // layout changes — can never kick off or restart a fade.
    private func setImage(_ image: UIImage?, fade: Bool) {
        let surface = isBackground ? "bg" : "fg"
        guard image !== currentImage else {
            print("[art] \(surface) same instance — no swap")
            return
        }

        // Every track change delivers the same cover twice: Sonos's own proxy
        // URL first, then the service's CDN URL once `getTrackInformation`
        // resolves. `imageIDKey` is what says those are the same cover, and it
        // is already the pipeline's cache id — but the two lookups hand back
        // distinct UIImage instances, so the identity check above lets both
        // through and the second one animates for no visible change. On a skip
        // that is two hard swaps; on a natural change it is two crossfades,
        // which reads as a fade to black. Keyed on the cover, one swap.
        let key = imageIDKey
        if image != nil, currentImage != nil, key == currentImageKey {
            print("[art] \(surface) same cover \(key) — no swap")
            return
        }
        currentImageKey = image == nil ? nil : key

        print("[art] \(surface) SWAP image=\(image == nil ? "nil" : "new") fade=\(fade)")
        if fade {
            withAnimation(.smooth(duration: defaultFadeDuration)) {
                currentImage = image
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentImage = image
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

/// Debug helper: Sonos proxy and CDN artwork URLs are long, and the tail is the
/// part that differs between two loads of the same artwork.
private func briefURL(_ url: URL?) -> String {
    guard let url else { return "nil" }
    return String(url.absoluteString.suffix(44))
}
