import OrderedCollections
import SonosKit
import SwiftUI

/// What's queued where the route points, for the trailing `queuePanel`:
/// this device's queue, or the chosen Sonos group's.
///
/// Sits beside the tab content the same way the bottom accessory does, and
/// follows the same route, so the two never disagree about what "next" means.
struct QueueNextUpView: View {
    private var route: PlaybackRoute { .shared }

    var body: some View {
        if let group = route.group {
            GroupNextUpView(group: group)
        } else {
            LocalNextUpView()
        }
    }
}

/// The device's queue, from `LocalPlaybackService`.
private struct LocalNextUpView: View {
    private var playback: LocalPlaybackService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Next Up")
                .font(.title3.bold())
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // A station is live: nothing follows it, so the panel reads as
            // empty rather than listing the station as a one-row queue.
            if playback.queue.isEmpty || playback.isPlayingStation {
                Spacer()
                Text(playback.isPlayingStation ? "Live radio — nothing queued" : "Nothing queued")
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
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Plays this song")
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

/// A Sonos group's queue. No volume: that's the player's.
private struct GroupNextUpView: View {
    let group: GroupRoom

    private var sonosService: SonosService { .shared }

    @State private var isLoading = false

    /// The current row is only meaningful while the speaker plays from its
    /// queue; on radio or TV the list is what would play if it went back.
    private var isQueueActive: Bool { group.playbackService == .queue }

    var body: some View {
        let queue = group.coordinatorRoom.queue

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next Up")
                    .font(.title3.bold())
                Text(group.nameWithCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if queue.isEmpty {
                Spacer()
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Nothing queued")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // By offset, as the device list is: a track queued
                        // twice shares one `id`.
                        ForEach(Array(queue.enumerated()), id: \.offset) { _, item in
                            QueueNextUpRow(
                                item: item,
                                isCurrent: isQueueActive && group.isNowPlaying(item)
                            )
                            .onTapGesture { play(item) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Plays this song")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .opacity(isQueueActive ? 1 : 0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .task(id: group.coordinatorID) {
            await load()
        }
        // The queue itself changes without the track moving — a Play Next,
        // a hand-off filling in behind the first track — and the speaker
        // reports that as a new count.
        .onChange(of: group.coordinatorRoom.queueTotal) {
            Task { await load() }
        }
        .onChange(of: group.coordinatorRoom.track.unique) {
            Task { await load() }
        }
    }

    private func load() async {
        isLoading = group.coordinatorRoom.queue.isEmpty
        defer { isLoading = false }
        if let service = await sonosService.playbackService(ip: group.ip) {
            group.playbackService = service
        }
        group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.ip))
    }

    /// Jumps the speaker to this row. `seek(trackNumber:)` points the
    /// transport back at the queue first if it had wandered off to radio.
    private func play(_ item: PlayableContent) {
        guard let position = item.metadata?.position else { return }
        HapticManager.shared.fireHaptic(.selection)
        Task {
            await sonosService.seek(trackNumber: position, on: group)
        }
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
