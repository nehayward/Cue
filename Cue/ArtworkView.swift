import Nuke
import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct ArtworkView: View {
    @Environment(AlertService.self) var alertService
    @Environment(\.displayScale) private var displayScale

    let group: GroupRoom
    var isDraggable: Bool = false
    var showBadge: Bool = true
    var shouldFade: Bool = false
    // Renders just the artwork — no badge, rounded-corner clip, shadow, or
    // alarm tracking. For the full-screen blurred background copies of the
    // player, where those decorations are invisible under the blur but still
    // cost render time on every frame of a crossfade.
    var isBackground: Bool = false
    /// Longest side, in points, the artwork is decoded at. The 500 pt default
    /// is shared with the lock screen artwork (see `ImageRequest.playerArtwork`);
    /// small tiles pass their own size so they don't each hold a ~4 MB bitmap.
    var decodeSize: CGFloat = ImageRequest.playerArtworkSize

    private let defaultFadeDuration: Double = 0.3
    @State private var alarmRunning: Bool = false
    @State private var currentImage: UIImage?
    /// `imageIDKey` of whatever `currentImage` is showing — the cover's identity
    /// rather than the URL it happened to arrive from. See `setImage`.
    @State private var currentImageKey: String?
    /// The group the two properties above describe. The Mac/iPad player reuses
    /// this view across selection changes (the container builds
    /// `LargePlayerView` without an id), so the loaded image outlives the room
    /// it came from. Without this, the newly selected room shows the previous
    /// room's cover — and the hold-through-a-track-change below keeps it there
    /// indefinitely.
    @State private var currentImageGroupID: String?

    /// True between a room switch and the `.task` below resolving that room's
    /// artwork, i.e. while the image state still describes the room we left.
    private var isShowingAnotherRoomsImage: Bool {
        currentImageGroupID != group.coordinatorID
    }

    var cornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 8 : 16
    }

    fileprivate var imageIDKey: String {
        group.coordinatorRoom.track.playerArtworkCacheKey
    }

    /// At the player's size this is `Track.playerArtworkRequest`, shared with
    /// the skip prefetch in SonosKit, so the covers it loads ahead are the ones
    /// found here.
    private var artworkRequest: ImageRequest? {
        guard let url = group.coordinatorRoom.track.artworkURL else { return nil }
        return .playerArtwork(url: url, imageID: imageIDKey, pointSize: decodeSize)
    }

    // Synchronous memory-cache lookup used as the fallback below. On a hit
    // the very first paint already shows the artwork — no placeholder flash
    // on Catalyst app re-open — without needing a custom init to seed @State.
    private var cachedImage: UIImage? {
        guard let artworkRequest else { return nil }
        return ImagePipeline.shared.cache.cachedImage(for: artworkRequest)?.image
    }

    // Prefer the loaded image; fall back to the cache so there's no gap
    // before `.task` runs. On a room switch `currentImage` is still the room
    // we left, so skip it and go straight to this room's own cache entry —
    // usually a hit, which swaps the cover in the same frame as the selection
    // instead of flashing the placeholder the way re-identifying the view did.
    private var displayImage: UIImage? {
        if isShowingAnotherRoomsImage { return cachedImage }
        return currentImage ?? cachedImage
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
                        .accessibilityLabel("Unmute")
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
                // Keyed on the room as well as the URL: a selection change reuses
                // this view, and the room we switch to can even be playing the
                // same URL as the one we left.
                .task(id: "\(group.coordinatorID)|\(group.coordinatorRoom.track.artworkURL?.absoluteString ?? "")") {
                    // Decide the fade up front. `shouldFade` is reliably false
                    // right after a user skip (LargePlayerView only flips it back
                    // true ~200ms later), so snapshotting here means a slow image
                    // load can't fade in after the fact. A room switch is never a
                    // crossfade either — two rooms' covers have no continuity.
                    let fade = shouldFade && !isShowingAnotherRoomsImage
                    guard let artworkRequest else {
                        // Hold the outgoing image while a track change is still
                        // in flight. Sonos reports the new item before it has
                        // fetched that item's art, so `artworkURL` is briefly
                        // nil — clearing here drops to the placeholder and back,
                        // which reads as a fade to black rather than a
                        // crossfade. A genuinely empty track (stopped, idle,
                        // TV) has no artwork to hold and still clears, and so
                        // does a room switch: there is nothing to hold on to
                        // when the image belongs to the room we just left.
                        if group.coordinatorRoom.track.isEmpty || isShowingAnotherRoomsImage {
                            setImage(nil, fade: fade)
                        }
                        return
                    }
                    if let cached = ImagePipeline.shared.cache.cachedImage(for: artworkRequest) {
                        setImage(cached.image, fade: fade)
                        return
                    }
                    if let shrunk = shrunkPlayerArtwork(for: artworkRequest) {
                        setImage(shrunk, fade: fade)
                        return
                    }
                    // The Sonos proxy for Spotify is unreliable right at track
                    // boundaries (the speaker may not have fetched the new art
                    // yet), and a skip can settle on that URL with nothing
                    // changing it again to restart this task. So a failure
                    // keeps the previous image — better than flashing a grey
                    // placeholder — and tries again a couple of times.
                    for attempt in 1...3 {
                        do {
                            let image = try await ImagePipeline.shared.image(for: artworkRequest)
                            setImage(image, fade: fade)
                            return
                        } catch {
                            // A newer URL took over; that task loads it.
                            guard !Task.isCancelled else { return }
                            #if DEBUG
                            print("ArtworkView: load \(attempt)/3 failed for \(imageIDKey): \(error)")
                            #endif
                        }
                        guard attempt < 3 else { return }
                        try? await Task.sleep(for: .seconds(2 * attempt))
                        guard !Task.isCancelled else { return }
                        // The player, or the skip prefetch, may have it by now.
                        if let shrunk = shrunkPlayerArtwork(for: artworkRequest) {
                            setImage(shrunk, fade: fade)
                            return
                        }
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

    /// A smaller tile's copy of the cover, made from the player-size one when
    /// that's already in memory: the player, or the skip prefetch in SonosKit,
    /// loads covers at `ImageRequest.playerArtworkSize`, and the thumbnail
    /// size is part of Nuke's cache key, so a sidebar tile never finds those.
    /// Without this the tile downloads the cover again from whatever URL the
    /// track has, which right after a skip is often the speaker's proxy that
    /// isn't serving it yet, while the player shows the prefetched cover.
    ///
    /// Shrunk and stored under the tile's own request rather than shown as is,
    /// so the tile doesn't keep a player-size bitmap alive after the cache
    /// lets it go.
    private func shrunkPlayerArtwork(for request: ImageRequest) -> UIImage? {
        guard decodeSize < ImageRequest.playerArtworkSize,
              let playerRequest = group.coordinatorRoom.track.playerArtworkRequest,
              let large = ImagePipeline.shared.cache.cachedImage(for: playerRequest, caches: .memory)?.image,
              large.size.width > 0, large.size.height > 0 else { return nil }
        let fit = min(decodeSize / large.size.width, decodeSize / large.size.height, 1)
        let size = CGSize(width: large.size.width * fit, height: large.size.height * fit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            large.draw(in: CGRect(origin: .zero, size: size))
        }
        ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: small), for: request, caches: .memory)
        return small
    }

    // The only place an artwork swap is animated. Scoping the animation to
    // this one transaction (instead of a persistent `.animation` modifier)
    // means unrelated body re-evaluations — playback ticks, mute toggles,
    // layout changes — can never kick off or restart a fade.
    private func setImage(_ image: UIImage?, fade: Bool) {
        // Change detection is by the cover's identity, not the UIImage
        // instance: every track change delivers the same cover twice — Sonos's
        // own proxy URL first, then the service's CDN URL once
        // `getTrackInformation` resolves — and the two cache lookups hand back
        // distinct instances, so an instance check let both through and the
        // second animated for no visible change. On a skip that was two hard
        // swaps; on a natural change, two crossfades, which read as a fade to
        // black. A nil image carries a nil key, so clears and first paints
        // fall out of the same comparison.
        // The room is part of that identity: two rooms can be playing the same
        // cover, and the swap still has to be recorded so the state stops
        // reading as the previous room's.
        let key = image == nil ? nil : imageIDKey
        guard key != currentImageKey || currentImageGroupID != group.coordinatorID else { return }
        currentImageKey = key
        // Recorded on a clear too. It marks which room this view's image state
        // belongs to, not which room an image came from — nil-ing it out here
        // left `isShowingAnotherRoomsImage` true in the room we are already in,
        // which suppressed the crossfade on whatever loaded next.
        currentImageGroupID = group.coordinatorID

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
