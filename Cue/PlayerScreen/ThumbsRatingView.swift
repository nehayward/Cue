import MusicSearchKit
import SonosKit
import SwiftUI

/// Pandora's thumbs up / thumbs down station feedback, shown by
/// `LikeButtonView` in place of the heart.
///
/// Deliberately not modelled on `LikeButtonView`'s toggle: a thumb is feedback
/// sent to the *station*, not a saved-tracks membership we can read back. SMAPI
/// exposes no "what did I rate this" query, so the selection is local state for
/// the current track and resets when the track changes — matching what the
/// Pandora app shows after a skip.
struct ThumbsRatingView: View {
    var group: GroupRoom

    private enum Thumb { case up, down }

    @Environment(SonosService.self) private var sonosService
    @State private var rated: Thumb?
    @State private var bounceTrigger = 0

    private var trackID: String { group.coordinatorRoom.track.trackID }

    var body: some View {
        HStack(spacing: 2) {
            thumbButton(
                .down,
                symbol: "hand.thumbsdown",
                help: "Thumbs Down",
                // Pandora stops playing a thumbed-down track, so the station
                // moves on — skip to match. Gated on the rating landing: a
                // failed call shouldn't cost the user the song they're on.
                action: {
                    guard await MusicSearchService.shared.thumbsDownPandoraTrack(trackID: trackID) else { return }
                    await sonosService.next(ip: group.coordinatorRoom.ip)
                }
            )

            thumbButton(
                .up,
                symbol: "hand.thumbsup",
                help: "Thumbs Up",
                action: { _ = await MusicSearchService.shared.thumbsUpPandoraTrack(trackID: trackID) }
            )
        }
        .task(id: group.coordinatorRoom.track.id) {
            // New track — clear the previous track's selection without
            // animating the symbols out.
            var transaction = Transaction(animation: .none)
            transaction.disablesAnimations = true
            withTransaction(transaction) { rated = nil }
        }
    }

    @ViewBuilder
    private func thumbButton(
        _ thumb: Thumb,
        symbol: String,
        help: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            guard rated != thumb else { return }
            rated = thumb
            bounceTrigger += 1
            HapticManager.shared.fireHaptic(thumb == .up ? .notification(.success) : .selection)
            Task { await action() }
        } label: {
            Label {
                Text(help)
            } icon: {
                Image(systemName: symbol)
                    .symbolVariant(rated == thumb ? .fill : .none)
            }
            .labelStyle(.iconOnly)
            .symbolEffect(.bounce, value: rated == thumb ? bounceTrigger : 0)
            .help(help)
            .accessibilityLabel(help)
        }
        .buttonBorderShape(.circle)
        .disabled(trackID.isEmpty)
        .tint(MusicService.pandora.brandColor.gradient)
    }
}
