import SonosKitMini
import SwiftUI

/// Cue Mini's menu: Cue's player, wherever it plays, drawn as the system's
/// Now Playing in the menu bar is: a row for the song, with the cover and
/// the transport beside it, then how far through, then a hairline over where
/// it plays and the Sonos group's volume. All as Cue (Mac) last wrote it
/// (`CueLink`). Cue not open, it says so and offers to open it.
struct CueNowPlayingCard: View {
    /// The menu is open: titles scroll only then.
    var isVisible: Bool
    /// The Sonos group Cue plays on, as Mini's speakers know it, for its
    /// volume. Nil on this Mac, whose volume is macOS's.
    var speakerGroup: Binding<SonosDevice>?

    @State private var link = CueLink.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                if !link.isCueRunning {
                    CueClosedView()
                } else if let state = link.state, let item = state.item {
                    CuePlayingView(state: state, item: item, cover: link.currentCover, isVisible: isVisible)
                } else {
                    CueIdleView()
                }
            }
            .padding(14)

            if let route = link.state?.route {
                Divider()
                CueRouteRow(route: route, speakerGroup: speakerGroup)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
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
            HStack(spacing: 8) {
                Button {
                    link.showPlayer()
                } label: {
                    HStack(spacing: 10) {
                        CueCover(image: cover)
                        VStack(alignment: .leading, spacing: 0) {
                            CueLine(text: item.title, font: .body.weight(.semibold), isVisible: isVisible)
                            CueLine(text: item.subtitle, font: .body, isVisible: isVisible)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .contentTransition(.identity)
                        .transaction { $0.animation = nil }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Show in Cue")

                CueTransport(state: state)
            }

            if state.clock.duration > 0 {
                CueProgressRow(state: state) { seconds in
                    link.send(.seek(seconds: state.clock.spanStart + seconds, itemID: item.id))
                }
            }
        }
    }
}

/// A line of the song's, scrolling while the menu is open if it's too long.
/// Both branches laid out alike, so the swap as the menu opens doesn't move
/// it, and the row's height is the same for a line that scrolls and one that
/// doesn't.
private struct CueLine: View {
    let text: String
    let font: Font
    let isVisible: Bool

    var body: some View {
        VStack(alignment: .leading) {
            if isVisible {
                MarqueeText(text, font: font)
            } else {
                Text(text)
                    .font(font)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 18)
    }
}

/// Where Cue plays, with the Sonos group's volume beside it: this Mac, a
/// speaker group, or where a hand-off is taking the song.
private struct CueRouteRow: View {
    let route: CueMiniNowPlaying.Route
    let speakerGroup: Binding<SonosDevice>?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                // As wide as it needs up to a limit, the volume taking the rest.
                Text(route.movingTo.map { "Moving to \($0)…" } ?? route.name)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let speakerGroup {
                VolumeControlView(device: speakerGroup)
                    .transaction { $0.animation = nil }
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(height: 24)
    }

    private var symbol: String {
        guard route.isSpeaker else { return "laptopcomputer" }
        return route.roomCount > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill"
    }
}

/// The cover, or Cue's mark in its place, with Cue's badge at its corner as
/// the system's rows have their app's.
private struct CueCover: View {
    let image: NSImage?

    private let side: CGFloat = 44

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .foregroundStyle(.quaternary)
                CueMark()
                    .fill(.secondary)
                    .frame(width: side * 0.32 * CueMark.aspectRatio, height: side * 0.32)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .bottomTrailing) {
            if image != nil {
                CueBadge()
                    .offset(x: 3, y: 3)
            }
        }
    }
}

private struct CueBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(white: 0.13))
            .overlay {
                CueMark()
                    .fill(.accent)
                    .frame(width: 9 * CueMark.aspectRatio, height: 9)
            }
            .frame(width: 17, height: 17)
    }
}

// MARK: - Progress

/// Shuffle, how far through, and Repeat, on one line: a book has no play
/// modes, and its bar runs the row's width.
private struct CueProgressRow: View {
    let state: CueMiniNowPlaying
    let onSeek: (TimeInterval) -> Void

    private var link: CueLink { .shared }

    var body: some View {
        HStack(spacing: 6) {
            if state.transport.showsPlayModes {
                shuffleButton
            }
            CueProgressBar(
                clock: state.clock,
                canScrub: state.transport.canScrub && state.isActive,
                onSeek: onSeek
            )
            if state.transport.showsPlayModes {
                repeatButton
            }
        }
        .buttonStyle(CueTransportButtonStyle())
        .disabled(!state.isActive)
    }

    private var shuffleButton: some View {
        Button {
            link.send(.setShuffle(!state.isShuffled))
        } label: {
            Image(systemName: "shuffle")
                .foregroundStyle(state.isShuffled ? AnyShapeStyle(.accent) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24, alignment: .leading)
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
                .frame(width: 24, height: 24, alignment: .trailing)
                .contentShape(.rect)
        }
        .help(state.repeatMode == .off ? "Repeat" : state.repeatMode == .all ? "Repeat One" : "Repeat Off")
    }
}

/// How far through, on the clock Cue sent: run on here, once a second
/// while it's moving. A drag or a click seeks when it can.
private struct CueProgressBar: View {
    let clock: CueMiniNowPlaying.Clock
    let canScrub: Bool
    let onSeek: (TimeInterval) -> Void

    /// The pointer's place while dragging, as a share of the bar.
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
        return HStack(spacing: 6) {
            Text(Self.format(shown))
                .fixedSize()
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
            Text("-" + Self.format(max(clock.duration - shown, 0)))
                .fixedSize()
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
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

/// Previous, Play and Next, as Cue's player has them: a book's ±15/30 s in
/// Previous's and Next's places, a live station without Previous or Next.
/// All of it rests while a hand-off holds the player.
private struct CueTransport: View {
    let state: CueMiniNowPlaying

    private var link: CueLink { .shared }
    private var transport: CueMiniNowPlaying.Transport { state.transport }

    var body: some View {
        HStack(spacing: 0) {
            previousButton
            playButton
            nextButton
        }
        .buttonStyle(CueTransportButtonStyle())
        .disabled(!state.isActive)
        // Next's glyph on the row's edge, over Repeat's: the button's width
        // runs past it.
        .padding(.trailing, -6)
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
                .font(.system(size: 20))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: state.isLoading)
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .help(state.isPlaying ? "Pause" : "Play")
    }

    private func transportButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 30, height: 34)
                .contentShape(.rect)
        }
        .help(help)
    }
}

/// The glyph dim until the pointer's on it, as the system's are in the menu
/// bar, and dimmer while it can't be pressed. A glyph that's on (Shuffle)
/// keeps its own colour.
private struct CueTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovering && isEnabled ? .primary : .secondary)
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
                .onHover { isHovering = $0 }
        }
    }
}

// MARK: - Nothing playing, Cue closed

/// Cue is open with nothing loaded.
private struct CueIdleView: View {
    var body: some View {
        HStack(spacing: 10) {
            CueCover(image: nil)
            Text("Not Playing")
                .font(.body.weight(.semibold))
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
        HStack(spacing: 10) {
            CueCover(image: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cue Isn't Open")
                    .font(.body.weight(.semibold))
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
