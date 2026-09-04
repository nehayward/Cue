import Defaults
import SonosKit
import SwiftUI
import VibesDS

/// Full-screen view of what's playing locally on this device, opened from the
/// tab bar accessory.
///
/// Modelled on `LargePlayerView` — same vertical rhythm (artwork, album line,
/// title, artist, scrubber, transport), same `VibeSlider` and
/// `.liveActivity` buttons — but driven by `LocalPlaybackService` instead of a
/// `GroupRoom`. All state is the `PlayableContent` the search returned, so
/// nothing here needs a lookup.
struct PlayerView: View {
    /// The same key the main window's panel uses, so showing the queue here
    /// shows it there too rather than the two disagreeing.
    @AppStorage(AppStorageKeys.queueInspectorVisible) private var showQueue: Bool = false

    private var playback: LocalPlaybackService { .shared }

    /// Matches `LargePlayerView`: the wide layout is for anything that isn't a
    /// phone, Catalyst included.
    private var isMacCatalystOrPad: Bool {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return true
        }
#if targetEnvironment(macCatalyst)
        return true
#else
        return false
#endif
    }

    var body: some View {
        VStack(alignment: .center) {
            if let item = playback.nowPlaying {
                ContentArtworkView(content: item, showMusicSource: false, preferredSize: 600)
                    .padding(.bottom, 12)
                    .frame(
                        minWidth: 0,
                        maxWidth: isMacCatalystOrPad ? 800 : 500,
                        minHeight: 0,
                        maxHeight: isMacCatalystOrPad ? .infinity : 400
                    )

                // Album line, in the slot `LargePlayerView` gives the
                // container/radio-station line. Fixed height so the layout
                // doesn't shift between tracks that have one and tracks
                // that don't.
                Text(item.metadata?.album ?? "")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.identity)
                    .frame(height: 12)

                Text(item.title)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .padding(.horizontal)

                Text(item.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal)

                VStack {
                    LocalPlaybackScrubber()
                    LocalMediaControlsView()
                }
                .geometryGroup()

                toolbar
                    .padding(.top, 8)
            } else {
                Spacer()
                ContentUnavailableView("Nothing Playing", systemImage: "iphone.radiowaves.left.and.right")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical)
        .safeAreaPadding(.bottom)
        // The same trailing panel the main window uses where there's room —
        // it shows and hides in place, and the artwork reflows around it —
        // and a half-height sheet on a phone, where a side panel would only
        // squeeze both halves.
        .queuePanel(isPresented: $showQueue) {
            QueueNextUpView()
        }
        .background {
            PlayerBackgroundView(content: playback.nowPlaying)
        }
        .fontDesign(.rounded)
    }

    /// The glass row under the transport, in the slot `LargePlayerView`
    /// gives its own toolbar: this device's volume, and the queue toggle. There's no close button — the cover zooms
    /// back into the mini player on a downward drag — and no stop button:
    /// pausing is the transport's job, and the tab bar accessory keeps
    /// the track around to resume.
    private var toolbar: some View {
        HStack(spacing: 20) {
            LocalVolumeSlider()
            Button {
                HapticManager.shared.fireHaptic(.selection)
                withAnimation {
                    showQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(showQueue ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Up Next")
            .accessibilityAddTraits(showQueue ? .isSelected : [])
            .disabled(playback.queue.isEmpty)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
        .glassToolbar()
    }
}

/// The scrubber, mirroring `LargePlayerView.PlaybackView`: `VibeSlider` over
/// elapsed / remaining, monospaced.
private struct LocalPlaybackScrubber: View {
    private var playback: LocalPlaybackService { .shared }

    /// Held only while dragging, so the poller's `progress` updates don't yank
    /// the thumb back under the finger mid-scrub.
    @State private var scrubPosition: TimeInterval?

    /// Twin of `LargePlayerView`'s: animating the fill is what makes playback
    /// tick along, but a track change drops the position to zero and animating
    /// *that* sweeps the bar backwards like a rewind.
    private var positionAnimation: Animation? {
        playback.progress < 2 ? nil : .interactiveSpring
    }

    private var duration: TimeInterval { max(playback.duration, 1) }

    var body: some View {
        VStack(spacing: 0) {
            VibeSlider(
                value: Binding(
                    get: { min(scrubPosition ?? playback.progress, duration) },
                    set: { scrubPosition = $0 }
                ),
                in: 0...duration,
                step: 1,
                baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 16 : 24,
                delayDrag: false,
                valueAnimation: positionAnimation
            ) { isEditing in
                guard !isEditing else { return }
                if let scrubPosition {
                    playback.seek(to: scrubPosition)
                }
                scrubPosition = nil
            }
            .frame(maxWidth: 500)
            .frame(height: 40)
            .foregroundStyle(.primary)

            HStack {
                let position = Duration.seconds(scrubPosition ?? playback.progress)
                let remaining = Duration.seconds(max(0, duration - (scrubPosition ?? playback.progress)))
                let pattern: Duration.TimeFormatStyle.Pattern =
                    duration > 3600 ? .hourMinuteSecond : .minuteSecond

                Text(position.formatted(.time(pattern: pattern)))
                    .contentTransition(.identity)
                Spacer()
                Text("-\(remaining.formatted(.time(pattern: pattern)))")
                    .contentTransition(.identity)
            }
            .frame(maxWidth: 500)
            .monospacedDigit()
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .opacity(playback.duration.isZero ? 0 : 1)
    }
}

/// Transport, mirroring `LargePlayerView.PlayerMediaControlsView`.
private struct LocalMediaControlsView: View {
    private var playback: LocalPlaybackService { .shared }

    var body: some View {
        HStack {
            Button {
                HapticManager.shared.fireHaptic(.selection)
                playback.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.liveActivity)

            Spacer()

            Button {
                HapticManager.shared.fireHaptic(.selection)
                playback.togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .scaledToFit()
                    .contentTransition(.symbolEffect(.automatic))
                    .symbolEffect(.pulse, isActive: playback.isLoading)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.liveActivity)

            Spacer()

            Button {
                HapticManager.shared.fireHaptic(.selection)
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.liveActivity)
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, 60)
    }
}

/// The blurred-artwork backdrop, mirroring `LargePlayerView`'s
/// `BackgroundViewCatalyst` / `BackgroundView`. Catalyst blurs the image
/// directly and lays a `UIVisualEffectView` over it; elsewhere the artwork is
/// scaled to fill under a thin material, which is cheaper on device.
private struct PlayerBackgroundView: View {
    let content: PlayableContent?

    var body: some View {
        ZStack {
            if let content {
#if targetEnvironment(macCatalyst)
                ContentArtworkView(content: content, showMusicSource: false, preferredSize: 600)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .saturation(1.3)
                    .blur(radius: 80)
                BlurView()
#else
                ContentArtworkView(content: content, showMusicSource: false, preferredSize: 600)
                    .saturation(1.3)
                    .aspectRatio(contentMode: .fill)
                Rectangle()
                    .foregroundStyle(.thinMaterial)
#endif
            }
        }
        .scaleEffect(1.3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
