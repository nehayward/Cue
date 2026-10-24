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
        Group {
            if let group = route.presentedGroup {
                GroupNextUpView(group: group)
            } else {
                LocalNextUpView()
            }
        }
        // Through a hand-off the rows are the source's, on their way out: a
        // tap or an edit would play or change a queue the hand-off has
        // already carried.
        .disabled(route.isHolding)
    }
}

/// The device's queue, from `LocalPlaybackService`: shuffle, repeat and a
/// clear in the header, and every row but the current track can be removed
/// (swipe, or the context menu), moved to play next, or dragged into a new
/// order, as a speaker's queue can in Clic. Played rows too: a song already
/// heard can be brought back up to play again.
///
/// While a station plays, the queue waits behind it (`station`) and the list
/// says so the way a speaker's does on radio: "Not Active" in the header,
/// the rows dimmed with no current one, and a row tapped goes back to the
/// queue there.
private struct LocalNextUpView: View {
    private var playback: LocalPlaybackService { .shared }

    @State private var editMode: EditMode = .inactive

    /// Kept small: the rows, the header's buttons and the scroll that
    /// follows the current song are views of their own, each reading only
    /// what it shows — a skip used to rebuild the whole 1,700-row list from
    /// here. This reads the queue and whether a station is in front of it.
    var body: some View {
        let isParked = playback.isPlayingStation
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Up")
                        .font(.title3.bold())
                    if isParked, !playback.queue.isEmpty {
                        Text("Not Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                // A station alone has no queue to shuffle or repeat.
                if !isParked || !playback.queue.isEmpty {
                    LocalNextUpControls(editMode: $editMode)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if playback.queue.isEmpty {
                Spacer()
                Text(isParked ? "Live radio — nothing queued" : "Nothing queued")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                LocalQueueList(editMode: $editMode)
                    .opacity(isParked ? 0.6 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Shuffle, repeat, and the edit and clear menu, for the header.
private struct LocalNextUpControls: View {
    private var playback: LocalPlaybackService { .shared }

    @Binding var editMode: EditMode
    @State private var clearConfirmation = false

    var body: some View {
        // A book has no shuffle or repeat: its files are its chapters, in
        // order, once.
        if !playback.isOnBookFile {
            modes
        }
        menu
    }

    @ViewBuilder
    private var modes: some View {
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
        .disabled(!playback.isShuffled && playback.upNextCount < 2)
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
    }

    private var menu: some View {
        Menu {
            Button {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                }
            } label: {
                Label(editMode.isEditing ? "Done" : "Edit",
                      systemImage: editMode.isEditing ? "checkmark" : "pencil")
            }
            // Played rows can be edited too, so anything beside the current
            // track will do.
            .disabled(playback.queue.count < 2 && !editMode.isEditing)

            Button(role: .destructive) {
                clearConfirmation = true
            } label: {
                Label("Clear Up Next", systemImage: "trash")
            }
            .disabled(playback.upNextCount == 0)
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
}

/// A queue row's identity: the song, and which copy of it in the queue.
///
/// Not a string: rebuilt for every row whenever the queue changes, and
/// describing the service enum into each one was a measurable part of a
/// skip with a long queue open.
private struct QueueRowID: Hashable {
    let service: MusicService
    let songID: String
    let occurrence: Int

    /// The current song's row, counted from the rows before it rather than
    /// by building all of them.
    @MainActor static func current(in playback: LocalPlaybackService) -> QueueRowID? {
        let index = playback.currentIndex
        guard playback.queue.indices.contains(index) else { return nil }
        let content = playback.queue[index].content
        let occurrence = playback.queue[..<index].reduce(0) { count, item in
            item.content.id == content.id && item.content.service == content.service ? count + 1 : count
        }
        return QueueRowID(service: content.service, songID: content.id, occurrence: occurrence)
    }
}

/// The queue's rows. Reads the queue and nothing else, so a skip — which
/// only moves `currentIndex` — leaves the list as it is; each row reads the
/// current song itself (`LocalQueueRow`).
private struct LocalQueueList: View {
    private var playback: LocalPlaybackService { .shared }

    @Binding var editMode: EditMode

    /// The queue's rows with an identity that follows the song rather than
    /// its position: keyed by position, a dragged row and every row between
    /// its old and new place changed identity, so the list swapped their
    /// contents instead of sliding the one row. The same song queued twice
    /// tells its copies apart by which occurrence each is.
    private var rows: [(id: QueueRowID, index: Int, item: PlayableContent)] {
        var occurrences: [QueueRowID: Int] = [:]
        return playback.queue.enumerated().map { index, item in
            let key = QueueRowID(service: item.content.service, songID: item.content.id, occurrence: 0)
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return (QueueRowID(service: key.service, songID: key.songID, occurrence: occurrence), index, item)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(rows, id: \.id) { row in
                    LocalQueueRow(index: row.index, item: row.item)
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
            .background {
                QueueScrollFollower(proxy: proxy, isEditing: editMode.isEditing)
            }
        }
    }
}

/// Opens the list on the current song, with what's played above it to
/// scroll back to, and follows it as the queue moves on. Not while editing:
/// a reorder shouldn't yank the list away. Nor for a played row moved or
/// removed above it, which moves the current song's index but not the song:
/// it follows the row's identity. Near the end of a short queue the list
/// can't scroll the current song all the way up, so the played ones above
/// it fill the space.
///
/// By row id through `ScrollViewReader`: `List` ignores
/// `ScrollPosition.scrollTo(id:)`, which only drives a `ScrollView`, and
/// this has to stay a `List` for swipe-to-remove and drag-to-reorder. A view
/// of its own, so following the current song doesn't make the list read it.
private struct QueueScrollFollower: View {
    private var playback: LocalPlaybackService { .shared }

    let proxy: ScrollViewProxy
    let isEditing: Bool

    var body: some View {
        Color.clear
            // After the first layout: scrolled in the same pass as the list
            // appears, it stays at the top.
            .task {
                guard let row = QueueRowID.current(in: playback) else { return }
                proxy.scrollTo(row, anchor: .top)
            }
            .onChange(of: QueueRowID.current(in: playback)) { _, row in
                guard !isEditing, let row else { return }
                // A turn later: when the change came from a tap on a row,
                // the list is still handling that tap and drops a scroll
                // asked for in the same pass.
                Task { @MainActor in
                    withAnimation(.snappy) { proxy.scrollTo(row, anchor: .top) }
                }
            }
    }
}

/// One queue row, with its swipes and menu. Reads the current song itself,
/// so a skip redraws the rows on screen and nothing else.
private struct LocalQueueRow: View {
    private var playback: LocalPlaybackService { .shared }

    let index: Int
    let item: PlayableContent

    var body: some View {
        let current = playback.currentIndex
        // The current track stays put: it's playing, or behind a station
        // it's where the queue picks up. Every other row, played ones
        // included, can go anywhere, and a played one sent to play next is
        // heard again.
        let isCurrent = index == current
        let canPlayNext = !isCurrent && index != current + 1
        // Behind a station the queue's song isn't playing, so no row is
        // current; a tap goes back to the queue from this one.
        QueueNextUpRow(item: item, isCurrent: isCurrent && !playback.isPlayingStation)
            .opacity(index < current ? 0.5 : 1)
            .onTapGesture { playback.play(at: index) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Plays this song")
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .moveDisabled(isCurrent)
            .deleteDisabled(isCurrent)
            .swipeActions(edge: .leading) {
                if canPlayNext {
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
                if !isCurrent {
                    Button(role: .destructive) {
                        withAnimation { playback.removeFromQueue(at: [index]) }
                    } label: {
                        Label("Remove", systemImage: "xmark")
                    }
                }
            }
            .contextMenu {
                if canPlayNext {
                    Button {
                        withAnimation { playback.moveToNext(at: index) }
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }
                }
                if !isCurrent {
                    Button(role: .destructive) {
                        withAnimation { playback.removeFromQueue(at: [index]) }
                    } label: {
                        Label("Remove", systemImage: "xmark")
                    }
                }
            }
    }
}

/// A Sonos group's queue. No volume: that's the player's.
///
/// Edited as the device's is, and as Clic edits a speaker's queue: every
/// row but the current track can be removed (swipe, or the context menu),
/// moved to play next, or dragged into a new order, played ones included.
private struct GroupNextUpView: View {
    let group: GroupRoom

    private var sonosService: SonosService { .shared }

    @State private var isLoading = false
    @State private var clearConfirmation = false
    @State private var editMode: EditMode = .inactive

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
                GroupQueueList(group: group, editMode: $editMode)
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
        // A book has no shuffle or repeat: its files are its chapters, in
        // order, once.
        if !AudiobookPlayer.shared.contains(group.coordinatorRoom.track.toPlayable) {
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
        }

        // Edit and Clear, as the device's header has them.
        Menu {
            Button {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                }
            } label: {
                Label(editMode.isEditing ? "Done" : "Edit",
                      systemImage: editMode.isEditing ? "checkmark" : "pencil")
            }
            .disabled(group.coordinatorRoom.queue.count < 2 && !editMode.isEditing)

            Button(role: .destructive) {
                clearConfirmation = true
            } label: {
                Label("Clear Queue", systemImage: "trash")
            }
            .disabled(group.coordinatorRoom.queue.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Queue Options")
        .help("Queue Options")
        .confirmationDialog("Clear Queue", isPresented: $clearConfirmation, titleVisibility: .hidden) {
            Button("Clear Queue", role: .destructive) {
                HapticManager.shared.fireHaptic(.buttonPress)
                withAnimation {
                    group.coordinatorRoom.queue.removeAll()
                    editMode = .inactive
                }
                Task {
                    try? await sonosService.clearQueue(group.coordinatorRoom.ip)
                }
            }
        }
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
}

/// A Sonos group's rows, in a `List` for swipe-to-remove and
/// drag-to-reorder. An edit shows at once and goes to the speaker, which
/// then has the last word: the queue is read back from it, since the rows
/// after the first one edited all have new positions.
private struct GroupQueueList: View {
    let group: GroupRoom
    @Binding var editMode: EditMode

    private var sonosService: SonosService { .shared }

    var body: some View {
        // Keyed by the song and which copy of it, as the device's rows are:
        // keyed by offset, a dragged row and every row it passed changed
        // identity, and the list swapped their contents instead of sliding
        // the one row.
        let rows = Array(group.coordinatorRoom.queue.keyedByOccurrence().enumerated())
        ScrollViewReader { proxy in
            List {
                ForEach(rows, id: \.element.key) { row in
                    GroupQueueRow(
                        group: group,
                        item: row.element.track,
                        playNext: { playNext(row.element.track, at: row.offset) },
                        remove: { remove(at: [row.offset]) }
                    )
                }
                .onDelete { offsets in
                    remove(at: offsets)
                }
                .onMove { source, destination in
                    move(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .environment(\.editMode, $editMode)
            .background {
                GroupQueueScrollFollower(group: group, proxy: proxy, isEditing: editMode.isEditing)
            }
        }
    }

    /// The speaker counts positions from 1, and `InsertBefore` is a place in
    /// the queue as it was, as `onMove`'s destination is.
    private func move(from source: IndexSet, to destination: Int) {
        let rows = Array(group.coordinatorRoom.queue)
        guard source.count == 1, let offset = source.first, rows.indices.contains(offset),
              let from = rows[offset].metadata?.position else { return }
        let insertBefore = destination < rows.count
            ? rows[destination].metadata?.position
            : (rows.last?.metadata?.position).map { $0 + 1 }
        guard let to = insertBefore, to != from, to != from + 1 else { return }
        var updated = rows
        updated.move(fromOffsets: source, toOffset: destination)
        withAnimation(.snappy) {
            group.coordinatorRoom.queue = OrderedSet(updated)
        }
        Task {
            try? await sonosService.reorderQueue(group, from: from, to: to)
            await refresh()
        }
    }

    /// Removes rows from the last up, so each removal leaves the positions
    /// of the ones still to go as they were.
    private func remove(at offsets: IndexSet) {
        let rows = Array(group.coordinatorRoom.queue)
        let valid = offsets.filter { rows.indices.contains($0) }
        let positions = valid.compactMap { rows[$0].metadata?.position }.sorted(by: >)
        guard !positions.isEmpty else { return }
        var updated = rows
        updated.remove(atOffsets: IndexSet(valid))
        withAnimation {
            group.coordinatorRoom.queue = OrderedSet(updated)
        }
        Task {
            for position in positions {
                try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
            }
            await refresh()
        }
    }

    /// Moves a row to play right after the current track: an upcoming one
    /// forward, or a played one back into Up Next to hear again.
    private func playNext(_ item: PlayableContent, at offset: Int) {
        guard let from = item.metadata?.position else { return }
        let current = group.coordinatorRoom.track.position
        let to = current + 1
        guard from != current, from != to else { return }
        var updated = Array(group.coordinatorRoom.queue)
        if updated.indices.contains(offset),
           let currentOffset = updated.firstIndex(where: { $0.metadata?.position == current }) {
            updated.move(fromOffsets: [offset], toOffset: currentOffset + 1)
            withAnimation {
                group.coordinatorRoom.queue = OrderedSet(updated)
            }
        }
        Task {
            try? await sonosService.reorderQueue(group, from: from, to: to)
            await refresh()
        }
    }

    /// Reads back the queue, with every row's new position, and where the
    /// speaker is in it. The queue goes in straight after the track: the
    /// current row is marked by matching the two, and with one read and not
    /// the other it marked its neighbour for a moment.
    private func refresh() async {
        let queue = OrderedSet(await sonosService.getQueue(ip: group.ip))
        try? await sonosService.updateTrackInformation(for: [group])
        group.coordinatorRoom.queue = queue
        if let total = try? await sonosService.getQueueTotal(group: group) {
            group.coordinatorRoom.queueTotal = total
        }
    }
}

/// One of a group's rows, with its swipes and menu. Reads the current track
/// itself, so a skip redraws the rows on screen and nothing else.
private struct GroupQueueRow: View {
    let group: GroupRoom
    let item: PlayableContent
    let playNext: () -> Void
    let remove: () -> Void

    var body: some View {
        // On radio or TV no row is current, and Play Next has no track to
        // follow.
        let isActive = group.playbackService == .queue
        let current = group.coordinatorRoom.track.position
        let position = item.metadata?.position
        let isCurrent = isActive && position == current
        let isPlayed = isActive && (position.map { $0 < current } ?? false)
        let canPlayNext = isActive && !isCurrent && position != current + 1
        QueueNextUpRow(item: item, isCurrent: isCurrent)
            .opacity(isPlayed ? 0.5 : 1)
            .onTapGesture { play() }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Plays this song")
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .moveDisabled(isCurrent)
            .deleteDisabled(isCurrent)
            .swipeActions(edge: .leading) {
                if canPlayNext {
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        playNext()
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }
                    .tint(.accentColor)
                }
            }
            // Any `swipeActions` turns off the Delete swipe `onDelete`
            // would synthesize, so the trailing one is spelled out.
            .swipeActions(edge: .trailing) {
                if !isCurrent {
                    Button(role: .destructive) {
                        remove()
                    } label: {
                        Label("Remove", systemImage: "xmark")
                    }
                }
            }
            .contextMenu {
                if canPlayNext {
                    Button {
                        playNext()
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }
                }
                if !isCurrent {
                    Button(role: .destructive) {
                        remove()
                    } label: {
                        Label("Remove", systemImage: "xmark")
                    }
                }
            }
    }

    /// Jumps the speaker to this row. `seek(trackNumber:)` points the
    /// transport back at the queue first if it had wandered off to radio.
    private func play() {
        guard let position = item.metadata?.position else { return }
        HapticManager.shared.fireHaptic(.selection)
        Task {
            await SonosService.shared.seek(trackNumber: position, on: group)
        }
    }
}

/// Opens a group's list on the current song and follows it to the next
/// one, as the device's does (`QueueScrollFollower`). By the song, not its
/// position: an edit above it moves its position but not the song, and the
/// rows' positions catch up a moment after the speaker's.
private struct GroupQueueScrollFollower: View {
    let group: GroupRoom
    let proxy: ScrollViewProxy
    let isEditing: Bool

    /// The current song's row, while the speaker plays from its queue.
    private var currentRow: String? {
        guard group.playbackService == .queue else { return nil }
        return group.coordinatorRoom.queue.occurrenceKey(forPosition: group.coordinatorRoom.track.position)
    }

    var body: some View {
        Color.clear
            // After the first layout, as the device's list does.
            .task {
                guard let row = currentRow else { return }
                proxy.scrollTo(row, anchor: .top)
            }
            .onChange(of: group.coordinatorRoom.track.unique) { follow() }
            .onChange(of: group.playbackService == .queue) { follow() }
            // The queue loading in under a list that opened empty.
            .onChange(of: group.coordinatorRoom.queue.isEmpty) { follow() }
    }

    private func follow() {
        guard !isEditing, let row = currentRow else { return }
        // A turn later, as the device's list does: a tap on a row is still
        // being handled and drops a scroll asked for in the same pass.
        Task { @MainActor in
            withAnimation(.snappy) { proxy.scrollTo(row, anchor: .top) }
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
