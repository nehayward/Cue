import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI
import VibesDS

/// Where You Left Off, at the top of each music library: the music a book
/// was started over, or the queue waiting behind a station, one tap from
/// playing again at the song and spot it was left on. Dragged sideways it
/// follows the finger, and let go far enough it's dismissed (a book's music
/// stays set aside, for Back to Music in the player's menu).
/// `MusicLeftOffSection` shows it, as a section header, and takes it away.
struct MusicLeftOffCard: View {
    /// How the card goes, before the list closes up over its room.
    enum Exit {
        /// Played: it shrinks down toward the player as it fades.
        case play
        /// Dismissed: it carries on the way it was dragged as it fades.
        case dismiss
    }

    let aside: LocalPlaybackService.SetAsideQueue
    /// Set as it goes, nil while it shows.
    let exit: Exit?
    let onExit: (Exit) -> Void

    /// Points dragged sideways, left negative.
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 0

    /// The room under the card, inside the header so the list closes up
    /// over it with the card (the section has no spacing of its own).
    private static let gap: CGFloat = 32

    /// How far a drag goes before letting go dismisses the card.
    private var dismissDistance: CGFloat { min(100, width / 3) }
    /// How far a drag goes for the card to fade most of the way.
    private static let fadeDistance: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where You Left Off")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                onExit(.play)
            } label: {
                HStack(spacing: 12) {
                    if let song = aside.nowPlaying {
                        ContentArtworkView(content: song, showMusicSource: false, preferredSize: 160, cornerRadius: 8)
                            .frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aside.title)
                            .font(.headline)
                            .lineLimit(1)
                        if let line = aside.queueLine ?? aside.songLine {
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(exit != nil)
            .accessibilityLabel("Play \(aside.title) from where you left it")
        }
        // A header's own text style (secondary, capitals in a grouped list)
        // isn't the card's.
        .foregroundStyle(.primary)
        .textCase(nil)
        .padding(16)
        .background(.fill.quaternary, in: .rect(cornerRadius: 20))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Played, it shrinks toward the bottom of the screen, where the
        // player is; dismissed, it carries on a little from where the finger
        // left it. It fades fast as it's dragged: the list clips it at the
        // edge of the rows, which faded it looks like going, not a wipe.
        .offset(x: exit == .dismiss ? drag - 60 : drag)
        .scaleEffect(exit == .play ? 0.85 : 1, anchor: .bottom)
        .opacity(exit == nil ? 1 - min(abs(drag) / Self.fadeDistance, 0.85) : 0)
        .sidewaysPan(
            isEnabled: exit == nil,
            onBegan: {},
            onChanged: { x in
                // Left only; to the right it gives a little and comes back.
                drag = x < 0 ? x : x / 4
            },
            onEnded: {
                if drag < -dismissDistance {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    onExit(.dismiss)
                } else {
                    withAnimation(.snappy) { drag = 0 }
                }
            }
        )
        .accessibilityAction(named: "Dismiss") { onExit(.dismiss) }
        .padding(.bottom, Self.gap)
    }
}
