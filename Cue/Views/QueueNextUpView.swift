import SonosKit
import SwiftUI

/// What's queued on this device, for the trailing `queuePanel`.
///
/// Reads `LocalPlaybackService` rather than a Sonos group's queue: this panel
/// sits beside the tab content the same way the bottom accessory does, and
/// both are about local playback.
struct QueueNextUpView: View {
    private var playback: LocalPlaybackService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Next Up")
                .font(.title3.bold())
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if playback.queue.isEmpty {
                Spacer()
                Text("Nothing queued")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(playback.queue.enumerated()), id: \.offset) { index, item in
                            QueueNextUpRow(
                                item: item,
                                isCurrent: index == playback.currentIndex
                            )
                            .onTapGesture { playback.play(at: index) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct QueueNextUpRow: View {
    let item: PlayableContent
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            ContentArtworkView(content: item, showMusicSource: false)
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let duration = item.metadata?.duration {
                Text(duration, format: .time(pattern: .minuteSecond))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isCurrent ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }
}
