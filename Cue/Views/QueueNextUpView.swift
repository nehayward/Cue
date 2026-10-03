import OrderedCollections
import SonosKit
import SwiftUI

/// What's queued where the route points, for the trailing `queuePanel`:
/// this device's queue, or the chosen Sonos group's.
///
/// Sits beside the tab content the same way the bottom accessory does, and
/// follows the same route, so the two never disagree about what "next" means.
/// The presented route, like the player: while a hand-off carries the queue
/// to a speaker, this keeps showing the queue being carried rather than the
/// speaker's old one.
struct QueueNextUpView: View {
    private var route: PlaybackRoute { .shared }

    var body: some View {
        if let group = route.presentedGroup {
            GroupNextUpView(group: group)
        } else {
            LocalNextUpView()
        }
    }
}

/// The device's queue, from `LocalPlaybackService`: shuffle, repeat and a
/// clear in the header, and the rows after the current track can be
/// removed (swipe, or the context menu), moved to play next, or dragged into
/// a new order. Played rows and the current one stay put.
private struct LocalNextUpView: View {
    private var playback: LocalPlaybackService { .shared }

    @State private var editMode: EditMode = .inactive
    @State private var clearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text("Next Up")
                    .font(.title3.bold())
                Spacer(minLength: 8)
                if !playback.isPlayingStation {
                    controls
                }
            }
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
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controls: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            withAnimation(.easeInOut(duration: 0.35)) {
                playback.setShuffle(!playback.isShuffled)
            }
        } label: {
            Label("Shuffle", systemImage: "shuffle")
                .labelStyle(.iconOnly)
        }
        // On or off at a glance, the way Repeat beside it reads. Untinted,
        // it drew in the accent colour and looked on all the time.
        .tint(playback.isShuffled ? Color.accentColor : Color.secondary)
        .foregroundStyle(playback.isShuffled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .accessibilityValue(playback.isShuffled ? "On" : "Off")
        // Off stays reachable with nothing left to shuffle.
        .disabled(!playback.isShuffled && playback.upNext.count < 2)
        .help(playback.isShuffled ? "Shuffle On" : "Shuffle Off")

        Button {
            HapticManager.shared.fireHaptic(.selection)
            playback.setRepeatMode(playback.repeatMode.next)
        } label: {
            Label("Repeat", systemImage: playback.repeatMode.systemImage)
                .labelStyle(.iconOnly)
                .contentTransition(.symbolEffect(.automatic))
        }
        .tint(playback.repeatMode == .off ? Color.secondary : Color.accentColor)
        .foregroundStyle(playback.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
        .accessibilityValue(playback.repeatMode.title)
        .help(playback.repeatMode.title)

        Menu {
            Button {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                }
            } label: {
                Label(editMode.isEditing ? "Done" : "Edit",
                      systemImage: editMode.isEditing ? "checkmark" : "pencil")
            }
            .disabled(playback.upNext.isEmpty && !editMode.isEditing)

            Button(role: .destructive) {
                clearConfirmation = true
            } label: {
                Label("Clear Up Next", systemImage: "trash")
            }
            .disabled(playback.upNext.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Queue Options")
        .help("Queue Options")
        // On the menu, so the confirmation points at the button it came
        // from. On the whole panel it floated over the artwork, aimed at the
        // sheet's grabber.
        .confirmationDialog("Clear Up Next", isPresented: $clearConfirmation, titleVisibility: .hidden) {
            Button("Clear Up Next", role: .destructive) {
                HapticManager.shared.fireHaptic(.buttonPress)
                withAnimation {
                    playback.clearUpNext()
                    editMode = .inactive
                }
            }
        } message: {
            Text("The current song keeps playing.")
        }
    }

    /// The queue's rows with an identity that follows the song rather than
    /// its position: keyed by position, a dragged row and every row between
    /// its old and new place changed identity, so the list swapped their
    /// contents instead of sliding the one row. The same song queued twice
    /// tells its copies apart by which occurrence each is.
    private var rows: [(id: String, index: Int, item: PlayableContent)] {
        var occurrences: [String: Int] = [:]
        return playback.queue.enumerated().map { index, item in
            let key = "\(item.content.service)/\(item.content.id)"
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return ("\(key)#\(occurrence)", index, item)
        }
    }

    /// The current song's row, which the list opens on.
    private var currentRowID: String? {
        rows.first { $0.index == playback.currentIndex }?.id
    }

    /// Opens on the current song, with what's played above it to scroll
    /// back to, and follows it as the queue moves on. Not while editing: a
    /// reorder shouldn't yank the list away. Near the end of a short queue
    /// the list can't scroll the current song all the way up, so the played
    /// ones above it fill the space.
    ///
    /// By row id through `ScrollViewReader`: `List` ignores
    /// `ScrollPosition.scrollTo(id:)`, which only drives a `ScrollView`, and
    /// this has to stay a `List` for swipe-to-remove and drag-to-reorder.
    private var list: some View {
        ScrollViewReader { proxy in
            rowList
                // After the first layout: scrolled in the same pass as the
                // list appears, it stays at the top.
                .task {
                    guard let currentRowID else { return }
                    proxy.scrollTo(currentRowID, anchor: .top)
                }
                .onChange(of: playback.currentIndex) {
                    guard !editMode.isEditing, let currentRowID else { return }
                    withAnimation(.snappy) { proxy.scrollTo(currentRowID, anchor: .top) }
                }
        }
    }

    private var rowList: some View {
        List {
            ForEach(rows, id: \.id) { row in
                let index = row.index
                let item = row.item
                let isUpcoming = index > playback.currentIndex
                QueueNextUpRow(
                    item: item,
                    isCurrent: index == playback.currentIndex
                )
                .opacity(index < playback.currentIndex ? 0.5 : 1)
                .onTapGesture { playback.play(at: index) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Plays this song")
                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(!isUpcoming)
                .deleteDisabled(!isUpcoming)
                .swipeActions(edge: .leading) {
                    if index > playback.currentIndex + 1 {
                        Button {
                            withAnimation { playback.moveToNext(at: index) }
                        } label: {
                            Label("Play Next", systemImage: "text.insert")
                        }
                        .tint(.accentColor)
                    }
                }
                // Any `swipeActions` turns off the Delete swipe `onDelete`
                // would synthesize, so the trailing one is spelled out.
                .swipeActions(edge: .trailing) {
                    if isUpcoming {
                        Button(role: .destructive) {
                            withAnimation { playback.removeFromQueue(at: [index]) }
                        } label: {
                            Label("Remove", systemImage: "xmark")
                        }
                    }
                }
                .contextMenu {
                    if isUpcoming {
                        if index > playback.currentIndex + 1 {
                            Button {
                                withAnimation { playback.moveToNext(at: index) }
                            } label: {
                                Label("Play Next", systemImage: "text.insert")
                            }
                        }
                        Button(role: .destructive) {
                            withAnimation { playback.removeFromQueue(at: [index]) }
                        } label: {
                            Label("Remove", systemImage: "xmark")
                        }
                    }
                }
            }
            .onDelete { offsets in
                withAnimation { playback.removeFromQueue(at: offsets) }
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    playback.moveInQueue(from: source, to: destination)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .environment(\.editMode, $editMode)
    }
}

/// A Sonos group's queue. No volume: that's the player's.
private struct GroupNextUpView: View {
    let group: GroupRoom

    private var sonosService: SonosService { .shared }

    @State private var isLoading = false
    @State private var clearConfirmation = false
    /// Where the list is scrolled, by row offset.
    @State private var position = ScrollPosition(idType: Int.self)

    /// The current row is only meaningful while the speaker plays from its
    /// queue; on radio or TV the list is what would play if it went back.
    private var isQueueActive: Bool { group.playbackService == .queue }

    var body: some View {
        let queue = group.coordinatorRoom.queue

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Up")
                        .font(.title3.bold())
                    Text(group.nameWithCount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                controls
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
                    .scrollTargetLayout()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                // Opens on the current song, as the device's list does, and
                // follows it — including once the queue has loaded.
                .scrollPosition($position, anchor: .top)
                .onAppear {
                    if let currentOffset { position.scrollTo(id: currentOffset, anchor: .top) }
                }
                .onChange(of: currentOffset) {
                    guard let currentOffset else { return }
                    withAnimation(.snappy) { position.scrollTo(id: currentOffset, anchor: .top) }
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

    @ViewBuilder
    private var controls: some View {
        let shuffleOn = group.playMode.contains(.shuffle)
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            var mode = group.playMode
            if shuffleOn { mode.remove(.shuffle) } else { mode.insert(.shuffle) }
            setPlayMode(mode)
        } label: {
            Label("Shuffle", systemImage: "shuffle")
                .labelStyle(.iconOnly)
        }
        .tint(shuffleOn ? Color.accentColor : Color.secondary)
        .foregroundStyle(shuffleOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .accessibilityValue(shuffleOn ? "On" : "Off")
        .help("Shuffle")

        Button {
            HapticManager.shared.fireHaptic(.selection)
            // Off → Repeat All → Repeat One → Off, as the queue screen does.
            var mode = group.playMode
            if mode.contains(.normal) && !mode.isRepeatEnabled {
                mode.remove(.normal)
                mode.insert(.repeatAll)
            } else if mode.isRepeatAllEnabled {
                mode.remove(.normal)
                mode.remove(.repeatAll)
                mode.insert(.repeatOne)
            } else {
                mode.remove(.repeatOne)
                mode.remove(.repeatAll)
            }
            setPlayMode(mode)
        } label: {
            Label("Repeat", systemImage: group.playMode.contains(.repeatOne) ? "repeat.1" : "repeat")
                .labelStyle(.iconOnly)
                .contentTransition(.symbolEffect(.automatic))
        }
        .tint(group.playMode.isRepeatEnabled ? Color.accentColor : Color.secondary)
        .foregroundStyle(group.playMode.isRepeatEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .accessibilityValue(group.playMode.repeatAccessibilityValue)
        .help("Repeat")

        Button {
            clearConfirmation = true
        } label: {
            Label("Clear Queue", systemImage: "trash")
                .labelStyle(.iconOnly)
        }
        .foregroundStyle(.secondary)
        .disabled(group.coordinatorRoom.queue.isEmpty)
        .help("Clear Queue")
        .confirmationDialog("Clear Queue", isPresented: $clearConfirmation, titleVisibility: .hidden) {
            Button("Clear Queue", role: .destructive) {
                HapticManager.shared.fireHaptic(.buttonPress)
                withAnimation {
                    group.coordinatorRoom.queue.removeAll()
                }
                Task {
                    try? await sonosService.clearQueue(group.coordinatorRoom.ip)
                }
            }
        }
    }

    /// The current song's place in the loaded queue, while the speaker plays
    /// from it.
    private var currentOffset: Int? {
        guard isQueueActive else { return nil }
        return group.coordinatorRoom.queue.firstIndex { group.isNowPlaying($0) }
    }

    /// Sets the mode optimistically, then reloads: shuffling reorders the
    /// speaker's queue.
    private func setPlayMode(_ mode: PlayMode) {
        group.playMode = mode
        Task {
            await sonosService.setPlayMode(group.ip, mode: mode)
            let queue = OrderedSet(await sonosService.getQueue(ip: group.ip))
            withAnimation(.easeInOut(duration: 0.35)) {
                group.coordinatorRoom.queue = queue
            }
        }
    }

    private func load() async {
        isLoading = group.coordinatorRoom.queue.isEmpty
        defer { isLoading = false }
        if let service = await sonosService.playbackService(ip: group.ip) {
            group.playbackService = service
        }
        group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.ip))
        group.playMode = await sonosService.playMode(ip: group.ip)
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
