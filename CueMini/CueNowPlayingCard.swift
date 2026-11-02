import SonosKitMini
import SwiftUI

/// The top of Cue Mini: Cue's player, wherever it plays. The song or book
/// on show, where it plays, its progress and transport, as Cue (Mac) last
/// wrote them (`CueLink`), with the Sonos group's volume under them when
/// it plays on one. Cue not open, it says so and offers to open it.
struct CueNowPlayingCard: View {
    /// The menu is open: titles scroll only then, as the speaker rows' do.
    var isVisible: Bool
    /// The Sonos group Cue plays on, as Mini's speakers know it, for its
    /// volume. Nil on this Mac, whose volume is macOS's.
    var speakerGroup: Binding<SonosDevice>?

    @State private var link = CueLink.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !link.isCueRunning {
                CueClosedView()
            } else if let state = link.state, let item = state.item {
                CuePlayingView(state: state, item: item, cover: link.currentCover, isVisible: isVisible)
            } else {
                CueIdleView(route: link.state?.route)
            }

            if let speakerGroup {
                VolumeControlView(device: speakerGroup)
                    .frame(height: 16)
                    .transaction { $0.animation = nil }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .foregroundStyle(Color(nsColor: .secondarySystemFill))
        }
        .fontDesign(.rounded)
    }
}

// MARK: - Playing

private struct CuePlayingView: View {
    let state: CueMiniNowPlaying
    let item: CueMiniNowPlaying.Item
    let cover: NSImage?
    let isVisible: Bool

    private var link: CueLink { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CueRouteLabel(route: state.route)
                Spacer()
                ShowInCueButton()
            }

            HStack(spacing: 12) {
                Button {
                    link.showPlayer()
                } label: {
                    CueCover(image: cover, side: 56)
                }
                .buttonStyle(.plain)
                .help("Show in Cue")

                VStack(alignment: .leading, spacing: 2) {
                    // As the speaker rows: both branches laid out alike, so
                    // the swap as the menu opens doesn't move the title.
                    VStack(alignment: .leading) {
                        if isVisible {
                            MarqueeText(item.title, font: .headline)
                        } else {
                            Text(item.title)
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.subtitle)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .contentTransition(.identity)
                .transaction { $0.animation = nil }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if state.clock.duration > 0 {
                CueProgressBar(
                    clock: state.clock,
                    canScrub: state.transport.canScrub && state.isActive
                ) { seconds in
                    link.send(.seek(seconds: state.clock.spanStart + seconds, itemID: item.id))
                }
            }

            CueTransport(state: state)
        }
    }
}

/// Where Cue plays: this Mac, a speaker group, or where a hand-off is
/// taking the song.
private struct CueRouteLabel: View {
    let route: CueMiniNowPlaying.Route

    var body: some View {
        Label {
            Text(route.movingTo.map { "Moving to \($0)…" } ?? route.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var symbol: String {
        guard route.isSpeaker else { return "laptopcomputer" }
        return route.roomCount > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill"
    }
}

private struct ShowInCueButton: View {
    var body: some View {
        Button {
            CueLink.shared.showPlayer()
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Show in Cue")
    }
}

/// The cover, or Cue's mark in its place.
private struct CueCover: View {
    let image: NSImage?
    let side: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .foregroundStyle(.quaternary)
                CueMark()
                    .fill(.secondary)
                    .frame(width: side * 0.32 * CueMark.aspectRatio, height: side * 0.32)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Progress

/// How far through, on the clock Cue sent: run on here, once a second
/// while it's moving. A drag or a click seeks when it can.
private struct CueProgressBar: View {
    let clock: CueMiniNowPlaying.Clock
    let canScrub: Bool
    let onSeek: (TimeInterval) -> Void

    /// The finger's place while dragging, as a share of the bar.
    @State private var dragFraction: Double?
    @State private var isHovering = false

    var body: some View {
        if clock.isRunning, dragFraction == nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(position: clock.position(at: context.date))
            }
        } else {
            content(position: clock.position(at: .now))
        }
    }

    private func content(position: TimeInterval) -> some View {
        let duration = max(clock.duration, 1)
        let fraction = dragFraction ?? min(max(position / duration, 0), 1)
        let shown = fraction * clock.duration
        return VStack(spacing: 2) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(.primary.opacity(0.8))
                        .frame(width: max(width * fraction, 0))
                }
                .frame(height: isHovering && canScrub || dragFraction != nil ? 6 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragFraction = min(max(value.location.x / max(width, 1), 0), 1)
                        }
                        .onEnded { value in
                            let fraction = min(max(value.location.x / max(width, 1), 0), 1)
                            onSeek(fraction * clock.duration)
                            dragFraction = nil
                        },
                    isEnabled: canScrub
                )
            }
            .frame(height: 12)
            .onHover { isHovering = $0 }
            .animation(.snappy(duration: 0.15), value: isHovering)

            HStack {
                Text(Self.format(shown))
                Spacer()
                Text("-" + Self.format(max(clock.duration - shown, 0)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Transport

/// Shuffle, Previous, Play, Next and Repeat, as Cue's player has them: a
/// book's ±15/30 s in Previous's and Next's places and no play modes, a
/// live station without Previous or Next. All of it rests while a
/// hand-off holds the player.
private struct CueTransport: View {
    let state: CueMiniNowPlaying

    private var link: CueLink { .shared }
    private var transport: CueMiniNowPlaying.Transport { state.transport }

    var body: some View {
        HStack(spacing: 0) {
            playModeSlot { shuffleButton }
            Spacer(minLength: 0)
            previousButton
            playButton
            nextButton
            Spacer(minLength: 0)
            playModeSlot { repeatButton }
        }
        .buttonStyle(.plain)
        .disabled(!state.isActive)
    }

    /// Shuffle's or Repeat's place, kept empty when they don't apply, so
    /// the transport stays centred.
    private func playModeSlot<Content: View>(@ViewBuilder _ button: () -> Content) -> some View {
        ZStack {
            if transport.showsPlayModes {
                button()
            }
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private var previousButton: some View {
        if let seconds = transport.skipBack {
            transportButton("gobackward.\(Int(seconds))", help: "Back \(Int(seconds)) Seconds") {
                link.skip(forward: false)
            }
        } else if transport.showsPrevious {
            transportButton("backward.fill", help: "Previous") {
                link.skip(forward: false)
            }
            .disabled(!transport.canGoBack)
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if let seconds = transport.skipForward {
            transportButton("goforward.\(Int(seconds))", help: "Forward \(Int(seconds)) Seconds") {
                link.skip(forward: true)
            }
        } else if transport.showsNext {
            transportButton("forward.fill", help: "Next") {
                link.skip(forward: true)
            }
            .disabled(!transport.hasNext)
        }
    }

    private var playButton: some View {
        Button {
            link.send(.togglePlayback)
        } label: {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.title)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: state.isLoading)
                .frame(width: 52, height: 40)
                .contentShape(.rect)
        }
        .help(state.isPlaying ? "Pause" : "Play")
    }

    private var shuffleButton: some View {
        Button {
            link.send(.setShuffle(!state.isShuffled))
        } label: {
            Image(systemName: "shuffle")
                .foregroundStyle(state.isShuffled ? AnyShapeStyle(.accent) : AnyShapeStyle(.secondary))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .help(state.isShuffled ? "Shuffle Off" : "Shuffle")
    }

    private var repeatButton: some View {
        Button {
            link.send(.setRepeat(state.repeatMode.next))
        } label: {
            Image(systemName: state.repeatMode == .one ? "repeat.1" : "repeat")
                .foregroundStyle(state.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.accent))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .help(state.repeatMode == .off ? "Repeat" : state.repeatMode == .all ? "Repeat One" : "Repeat Off")
    }

    private func transportButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 40)
                .contentShape(.rect)
        }
        .help(help)
    }
}

// MARK: - Nothing playing, Cue closed

/// Cue is open with nothing loaded.
private struct CueIdleView: View {
    let route: CueMiniNowPlaying.Route?

    var body: some View {
        HStack(spacing: 12) {
            CueCover(image: nil, side: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Not Playing")
                    .font(.headline)
                if let route {
                    CueRouteLabel(route: route)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Cue") {
                CueLink.shared.openCue()
            }
            .controlSize(.small)
        }
    }
}

/// Cue isn't open: there's no player to show.
private struct CueClosedView: View {
    var body: some View {
        HStack(spacing: 12) {
            CueCover(image: nil, side: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cue Isn't Open")
                    .font(.headline)
                Text("Open Cue to play music on this Mac or your speakers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Cue") {
                CueLink.shared.openCue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}
