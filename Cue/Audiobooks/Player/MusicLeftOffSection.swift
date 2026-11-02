import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// `MusicLeftOffCard` as a section of its own, at the top of a music
/// library, apart from the library's rows so it doesn't cut into their
/// group: the music a book was started over, or the queue waiting behind a
/// station, on this device.
///
/// The card goes in two steps: it leaves in place (shrinking toward the
/// player, or off the way it was dragged), then the list closes up over
/// its room. A list can't animate that last part itself: a section taken
/// away crossfaded every row under it from the old place to the new, and a
/// row or header shrinking moved them in steps. So the section goes with no
/// animation and, in the same update, its height becomes the list's top
/// padding (`musicLeftOffRoom()`), which then springs to nothing: a scroll
/// view's inset follows every frame.
struct MusicLeftOffSection: View {
    @State private var player = AudiobookPlayer.shared
    /// The card on its way out, as it was shown: Play takes the music back
    /// before the card has gone.
    @State private var leaving: Leaving?
    /// The header's height, the room the list closes up over.
    @State private var height: CGFloat = 0

    private struct Offer {
        var aside: LocalPlaybackService.SetAsideQueue
        /// Behind a station, rather than set aside for a book.
        var isRadio: Bool
    }

    private struct Leaving {
        var offer: Offer
        var exit: MusicLeftOffCard.Exit
    }

    private var offer: Offer? {
        if let aside = player.musicLeftOff {
            return Offer(aside: aside, isRadio: false)
        }
        // The station first: only while one plays does this read the queue,
        // which every skip and edit changes.
        let local = LocalPlaybackService.shared
        guard local.isPlayingStation, PlaybackRoute.shared.destination == .device,
              let aside = local.queueBehindStation,
              // A book's files waiting behind a station aren't music to go
              // back to: Back to Book is the way to them.
              !player.contains(aside.nowPlaying) else { return nil }
        return Offer(aside: aside, isRadio: true)
    }

    var body: some View {
        if let shown = leaving?.offer ?? offer {
            Section {
            } header: {
                MusicLeftOffCard(aside: shown.aside, exit: leaving?.exit) { exit in
                    leave(shown, by: exit)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                // On the header's outermost view, or its own insets come
                // back: as wide as the library's group under it.
                .listRowInsets(EdgeInsets())
            }
            // The room under the card is in its header, so the list closes
            // up over all of it.
            .listSectionSpacing(0)
        }
    }

    private func leave(_ offer: Offer, by exit: MusicLeftOffCard.Exit) {
        guard leaving == nil else { return }
        let local = LocalPlaybackService.shared
        // The list closes up as soon as the card is all but gone, not once
        // its spring has settled, which read as a pause.
        withAnimation(.smooth(duration: 0.25), completionCriteria: .logicallyComplete) {
            leaving = Leaving(offer: offer, exit: exit)
        } completion: { [height] in
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                leaving = nil
                MusicLeftOffRoom.shared.close(height)
            }
        }
        // Hidden from now on; the copy in `leaving` draws it out.
        if offer.isRadio {
            local.dismissQueueBehindStation()
        } else {
            local.markSetAsideQueue(dismissed: true)
        }
        guard exit == .play else { return }
        Task {
            do {
                if offer.isRadio {
                    try await local.returnToQueueBehindStation()
                } else {
                    try await player.returnToMusic()
                }
            } catch {
                // Still where it was: the card comes back. (A station's
                // queue stays dismissed: the station plays on.)
                if !offer.isRadio {
                    withAnimation { local.markSetAsideQueue(dismissed: false) }
                }
            }
        }
    }
}

/// The room Where You Left Off leaves as it goes, for the list it was in to
/// close up over (`musicLeftOffRoom()`).
@MainActor
@Observable
final class MusicLeftOffRoom {
    static let shared = MusicLeftOffRoom()

    struct Closing: Equatable {
        let id = UUID()
        let height: CGFloat
    }

    /// The last card gone, nil before any has.
    private(set) var closing: Closing?

    func close(_ height: CGFloat) {
        closing = Closing(height: height)
    }
}

extension View {
    /// On a list holding `MusicLeftOffSection`: as the card's section goes,
    /// its height becomes this list's top padding, which springs away, so
    /// the rows under it glide up.
    func musicLeftOffRoom() -> some View {
        modifier(MusicLeftOffRoomPadding())
    }
}

private struct MusicLeftOffRoomPadding: ViewModifier {
    @State private var room = MusicLeftOffRoom.shared

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: room.closing) { content, padding in
            content.safeAreaPadding(.top, padding)
        } keyframes: { _ in
            KeyframeTrack {
                // At once, in the update that takes the section away.
                MoveKeyframe(room.closing?.height ?? 0)
                SpringKeyframe(0, duration: 0.4, spring: .smooth)
            }
        }
    }
}
