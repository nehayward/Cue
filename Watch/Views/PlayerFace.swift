import SwiftUI
import WatchKit

/// The time into a song (or a book's chapter) against its length, as read
/// `at` a moment, running on at `rate` while it plays.
struct PlayerClock: Equatable {
    var elapsed: TimeInterval
    var duration: TimeInterval
    var at: Date
    var rate: Double = 1
    var isPlaying: Bool

    func elapsed(at date: Date) -> TimeInterval {
        let run = isPlaying ? max(date.timeIntervalSince(at), 0) * rate : 0
        return min(max(elapsed + run, 0), duration)
    }
}

/// One player's face, the watch's and the iPhone's alike, filling the
/// screen as the system's Now Playing does: the cover by the title (a
/// book's chapter, or the song) and what it's from (the book, or the
/// artist), the transport large in the middle as glass buttons that tap
/// back, a thin line of how far in with the time left, and along the
/// bottom the sleep timer and a book's speed, where it plays (a tap moves
/// it), and the volume on the Digital Crown. The bottom row is the face's
/// own, not the toolbar's: a bottom bar in the toolbar went missing when a
/// screen pushed over the player was swiped back. The screen puts it on the
/// cover's gradient.
struct PlayerFace<Cover: View>: View {
    let title: String
    let subtitle: String
    let clock: PlayerClock?
    let isPlaying: Bool
    /// A book: back 15 s and ahead 30 s for Previous and Next.
    let isBook: Bool
    let canGoBack: Bool
    let hasNext: Bool
    let place: PlaybackPlace
    let hasSleepTimer: Bool
    /// Whose volume the Digital Crown sets: this watch's, or the iPhone's.
    let volume: WKInterfaceVolumeControl.Origin
    let previous: () -> Void
    let playPause: () -> Void
    let next: () -> Void
    /// The sleep timer and a book's speed.
    let options: () -> Void
    /// Play On: where it plays.
    let choosePlace: () -> Void
    @ViewBuilder let cover: Cover

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                cover
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 4)
            transport
            Spacer(minLength: 4)
            if let clock {
                PlayerProgressBar(clock: clock)
                    .padding(.bottom, 10)
            }
            bottomRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The bottom row sits in the screen's bottom corners, as a bottom
        // bar's buttons do.
        .ignoresSafeArea(edges: .bottom)
    }

    /// Previous, play or pause, Next; a book's back 15 s and ahead 30 s.
    /// Play is the screen's primary action, so double tap presses it.
    private var transport: some View {
        HStack(spacing: 0) {
            Button {
                tapped(previous)
            } label: {
                TransportIcon(symbol: isBook ? "gobackward.15" : "backward.fill", size: 19, side: 46)
            }
            .accessibilityLabel(isBook ? "Back 15 Seconds" : "Previous")
            .disabled(!canGoBack)
            Spacer(minLength: 0)
            Button {
                tapped(playPause)
            } label: {
                TransportIcon(symbol: isPlaying ? "pause.fill" : "play.fill", size: 26, side: 60)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .primaryHandGesture()
            Spacer(minLength: 0)
            Button {
                tapped(next)
            } label: {
                TransportIcon(symbol: isBook ? "goforward.30" : "forward.fill", size: 19, side: 46)
            }
            .accessibilityLabel(isBook ? "Ahead 30 Seconds" : "Next")
            .disabled(!hasNext)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    /// The sleep timer and speed bottom left, where it plays in the middle,
    /// the volume bottom right.
    private var bottomRow: some View {
        HStack(spacing: 0) {
            Button(action: options) {
                Image(systemName: hasSleepTimer ? "moon.zzz.fill" : "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .glassCircle(side: 38)
            }
            .accessibilityLabel(isBook ? "Sleep Timer and Speed" : "Sleep Timer")
            Spacer(minLength: 0)
            Button(action: choosePlace) {
                PlaceGlyph(place: place)
                    .font(.system(size: 15, weight: .semibold))
                    .glassCircle(side: 38)
            }
            .accessibilityHint("Choose where it plays")
            Spacer(minLength: 0)
            VolumeControl(origin: volume)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        // Each in the corner the top bar's buttons mirror.
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func tapped(_ action: () -> Void) {
        WKInterfaceDevice.current().play(.click)
        action()
    }
}

/// A transport button's glyph, in a glass circle `side` across.
private struct TransportIcon: View {
    let symbol: String
    let size: CGFloat
    let side: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .glassCircle(side: side)
    }
}

extension View {
    /// A button's label in a round pane of glass `side` across, as the
    /// system's player and the top bar have (watchOS 26); a plain tint
    /// before. Sized here: the glass button style pads its label to its own
    /// size.
    @ViewBuilder
    func glassCircle(side: CGFloat) -> some View {
        let sized = frame(width: side, height: side)
            .contentShape(Circle())
        if #available(watchOS 26.0, *) {
            sized.glassEffect(.regular.interactive(), in: Circle())
        } else {
            sized.background(Circle().fill(.white.opacity(0.15)))
        }
    }
}

/// A thin line of how far in, with the time left beside it (at the speed
/// it plays at, as the iPhone counts a book's), running while it plays —
/// once a second, which the system slows itself with the wrist down.
struct PlayerProgressBar: View {
    let clock: PlayerClock

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let time = clock.elapsed(at: context.date)
            let fraction = clock.duration > 0 ? time / clock.duration : 0
            HStack(spacing: 6) {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * fraction)
                        }
                    }
                Text("-" + Self.format(timeLeft(at: time)))
                    .font(.system(.caption2, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.format(timeLeft(at: clock.elapsed(at: .now)))) left")
    }

    private func timeLeft(at time: TimeInterval) -> TimeInterval {
        max(clock.duration - time, 0) / max(clock.rate, 0.1)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: pattern))
    }
}

/// Where a player plays, as a glyph: this watch, the iPhone, or a Sonos
/// group the iPhone plays to.
enum PlaybackPlace: Equatable {
    case watch
    case iPhone
    case speaker(String)

    var symbol: String {
        switch self {
        case .watch: "applewatch"
        case .iPhone: "iphone"
        case .speaker: "hifispeaker.fill"
        }
    }

    var name: String {
        switch self {
        case .watch: "Apple Watch"
        case .iPhone: "iPhone"
        case let .speaker(name): name
        }
    }
}

/// The glyph of where it plays, named for VoiceOver.
struct PlaceGlyph: View {
    let place: PlaybackPlace

    var body: some View {
        Image(systemName: place.symbol)
            .accessibilityLabel("On \(place.name)")
    }
}

/// The system's volume control, which the Digital Crown turns: this
/// watch's own output (`.local`), or the iPhone's (`.companion`).
struct VolumeControl: WKInterfaceObjectRepresentable {
    let origin: WKInterfaceVolumeControl.Origin

    func makeWKInterfaceObject(context: Context) -> WKInterfaceVolumeControl {
        let control = WKInterfaceVolumeControl(origin: origin)
        control.setTintColor(.white)
        return control
    }

    func updateWKInterfaceObject(_ control: WKInterfaceVolumeControl, context: Context) {
        control.focus()
    }
}

/// The chapter playing, filled behind its row as far as it's been heard,
/// running while it plays, as the iPhone's chapter rows are. Other rows
/// keep the list's own background (`listRowBackground(nil)`).
struct ChapterRowFill: View {
    /// The time into the chapter.
    let clock: PlayerClock

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = clock.duration > 0 ? clock.elapsed(at: context.date) / clock.duration : 0
            shape
                .fill(Color.accentColor.opacity(0.15))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .clipShape(shape)
        }
    }
}
