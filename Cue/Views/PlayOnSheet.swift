import Defaults
import SonosKit
import SwiftUI

/// Where playback goes, and how loud each place is: the sheet behind the Play
/// On button while Sonos is on.
///
/// Laid out like the system's AirPlay picker: what's playing on top, then This
/// Device and every active room. Each row is its own volume slider — the fill
/// is the level, and a sideways drag anywhere on the row moves it — so a
/// group's rooms can be balanced from one place, and a room playing something
/// else can be turned down without leaving the sheet.
///
/// A tap is the route. On this device, tapping a room moves playback to the
/// group that room is in. On a speaker, the rooms are toggles on the group's
/// membership (`GroupMembership`, the same rules as the press-and-hold group
/// menu): tap to add one, tap again to drop it. This Device leaves the
/// speakers.
///
/// The rows sit in a scroll view, so every drag has to say whose it is. The
/// first few points of movement decide (`VolumeRouteRow`): mostly sideways is
/// the row's volume, and the list holds still until the finger lifts; mostly
/// up or down is the list's. The list's scroll phase is watched as well, so
/// a touch that lands while it is still moving only stops it — it never
/// regroups and never changes a volume.
struct PlayOnSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Singletons, not the environment: the button that presents this sits in
    /// the tab bar accessory, outside what `withEnvironments()` installs.
    private var sonosService: SonosService { .shared }
    private var route: PlaybackRoute { .shared }

    /// A switch waiting on the transfer prompt's answer.
    @State private var pending: PendingSwitch?
    /// False from the moment the list starts moving until it comes to rest.
    @State private var listIsSettled = true
    /// The row being dragged for volume; the list doesn't scroll meanwhile.
    @State private var adjustingRowID: String?
    @State private var roomVolumes = RoomVolumeWriter()

    private static let deviceRowID = "device"

    private var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayOnHeader()
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 10) {
                    deviceRow
                    speakerRows
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDisabled(adjustingRowID != nil)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .idle:
                    listIsSettled = true
                case .tracking:
                    // A finger landing. Says nothing yet, and mustn't clear
                    // a fling it is about to catch.
                    break
                default:
                    listIsSettled = false
                }
            }

            if let group = route.group, activeRooms.count > 1 {
                groupingBar(GroupMembership(group: group))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $pending) { pending in
            RouteTransferPrompt(target: pending.target) { carrying in
                self.pending = nil
                route.switchTo(pending.target, carrying: carrying)
            }
        }
        .task { await refreshRoomVolumes() }
        .onAppear {
            // The rooms are where a pick goes from here, which is the head
            // start: the hand-off can skip a read.
            if route.destination == .device {
                route.prefetchTargets()
            }
        }
    }

    // MARK: - Rows

    private var deviceRow: some View {
        let volume = DeviceVolume.shared
        return VolumeRouteRow(
            title: "This Device",
            symbol: Self.deviceSymbol,
            mark: route.destination == .device ? .checkmark : .empty,
            // While a speaker holds the system volume, the device's own
            // level isn't the one the buttons move: no fill to drag.
            level: volume.isAvailable ? volume.level : nil,
            listIsSettled: listIsSettled,
            onTap: { select(.device) },
            onLevel: { volume.set($0) },
            onAdjusting: { setAdjusting(Self.deviceRowID, $0) }
        )
    }

    @ViewBuilder
    private var speakerRows: some View {
        let rooms = activeRooms
        if rooms.isEmpty {
            Text(sonosService.isSearching ? "Looking for speakers…" : "No speakers found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
        } else {
            let membership = route.group.map { GroupMembership(group: $0) }
            ForEach(rooms) { room in
                roomRow(room, membership: membership)
            }
        }
    }

    private func roomRow(_ room: Room, membership: GroupMembership?) -> some View {
        let mark: VolumeRouteRow.Mark = if let membership {
            membership.isMember(room) ? .checkedCircle : .circle
        } else {
            .empty
        }
        return VolumeRouteRow(
            title: room.name,
            subtitle: note(for: room),
            symbol: room.isSoundbar ? "tv.and.hifispeaker.fill" : "hifispeaker.fill",
            mark: mark,
            level: room.volume / 100,
            isMuted: room.isMuted,
            listIsSettled: listIsSettled,
            onTap: { tap(room, membership: membership) },
            onLevel: { roomVolumes.set(room, to: $0 * 100) },
            onAdjusting: { setAdjusting(room.id, $0) }
        )
    }

    /// The line under a room's name, for a room that isn't part of where
    /// playback is: what its own group is playing, or who it's grouped with.
    /// Those are what a tap on it would take over.
    private func note(for room: Room) -> Text? {
        if room.isMuted { return Text("Muted") }
        guard let group = sonosService.groups.first(where: { group in group.rooms.contains { $0.id == room.id } }),
              group.coordinatorID != route.destination.groupID else { return nil }
        let track = group.coordinatorRoom.track
        if group.coordinatorRoom.isPlaying, !track.isEmpty {
            return Text("\(Image(systemName: "play.fill")) \(track.song)")
        }
        let others = group.rooms.filter { $0.id != room.id }.map(\.name)
        guard !others.isEmpty else { return nil }
        return Text("With \(others.formatted(.list(type: .and)))")
    }

    private func groupingBar(_ membership: GroupMembership) -> some View {
        HStack(spacing: 12) {
            Button {
                membership.groupEverywhere()
            } label: {
                Label("Everywhere", systemImage: "hifispeaker.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .glassButton()
            .disabled(membership.allGrouped)

            Button {
                membership.ungroupAll()
            } label: {
                Label("Ungroup All", systemImage: "hifispeaker.fill")
                    .frame(maxWidth: .infinity)
            }
            .glassButton()
            .disabled(!membership.canUngroup)
        }
        .font(.subheadline.weight(.semibold))
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func tap(_ room: Room, membership: GroupMembership?) {
        if let membership {
            membership.toggle(room)
        } else if let group = sonosService.groups.first(where: { group in group.rooms.contains { $0.id == room.id } }) {
            select(.group(group.coordinatorID))
        }
    }

    private func select(_ target: PlayDestination) {
        guard target != route.destination else { return }
        if target == .device, !FeatureGate.shared.isAvailable(.onDevicePlayback) {
            // The paywall is a full-screen cover off the root, and can't go
            // up over this sheet: close it first.
            if FeatureGate.shared.needsSuper(.onDevicePlayback) {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    FeatureGate.shared.presentPaywall()
                }
            }
            return
        }
        HapticManager.shared.fireHaptic(.selection)
        let preference = QueueTransferPreference.current
        if preference == .ask, route.hasSomethingToCarry(to: target) {
            pending = PendingSwitch(target: target)
        } else {
            route.switchTo(target, carrying: preference != .never)
        }
    }

    private func setAdjusting(_ id: String, _ isAdjusting: Bool) {
        if isAdjusting {
            adjustingRowID = id
        } else if adjustingRowID == id {
            adjustingRowID = nil
        }
    }

    /// The monitor keeps every room's level current, but only while it runs;
    /// one read on open means no row starts out at a stale level.
    private func refreshRoomVolumes() async {
        let sonos = SonosService.shared
        for group in sonos.groups {
            await sonos.updateRoomVolumes(for: group)
        }
    }

    private static var deviceSymbol: String {
#if os(visionOS)
        return "visionpro"
#elseif targetEnvironment(macCatalyst)
        return "laptopcomputer"
#else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
#endif
    }
}

// MARK: - Header

/// What's playing where the route points, as the AirPlay picker shows it.
private struct PlayOnHeader: View {
    @Environment(\.dismiss) private var dismiss

    private var route: PlaybackRoute { .shared }
    private var playback: LocalPlaybackService { .shared }

    /// The speaker's track on a group, this device's display item otherwise
    /// (a station reads as the song on air, as it does in the player).
    private var item: PlayableContent? {
        if let group = route.group {
            let track = group.coordinatorRoom.track
            return track.isEmpty ? nil : track.toPlayable
        }
        return playback.nowPlayingDisplay
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let item {
                    ContentArtworkView(content: item, showMusicSource: false)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.fill.tertiary)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let item {
                        Text(item.title)
                    } else {
                        Text("Not Playing")
                    }
                }
                .font(.headline)
                .lineLimit(1)

                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if route.isSwitching {
                ProgressView()
            }

#if targetEnvironment(macCatalyst)
            // A Mac sheet has no swipe to close it, and a click outside
            // doesn't either.
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
#endif
        }
    }

    /// The artist, or where it plays when there's no artist to show.
    private var subtitle: Text {
        if let subtitle = item?.subtitle, !subtitle.isEmpty { return Text(subtitle) }
        if let group = route.group { return Text(group.nameWithCount) }
        return Text("This Device")
    }
}

// MARK: - Row

/// One row of the Play On sheet: a destination that is also its own volume
/// slider, the way the system's AirPlay picker draws one.
///
/// One drag gesture does the tap, the volume and nothing at all, decided by
/// how the touch moves. Under `decisionDistance` it is still undecided, and
/// lifting there is a tap. Past it, mostly sideways is volume — measured from
/// that point, so the fill doesn't jump by the distance it took to decide —
/// and anything else is left to the list. It runs simultaneously with the
/// scroll view's own pan, so a vertical drag that starts on a row still
/// scrolls, and the sheet stops the list scrolling while a volume drag runs.
///
/// The drag's bookkeeping is `@State`, and `isTouching` is `@GestureState`
/// next to it: a gesture the system cancels never calls `onEnded`, but it
/// always resets its gesture state, which is what ends a cancelled drag.
struct VolumeRouteRow: View {
    enum Mark {
        /// Nothing trailing: a route to switch to.
        case empty
        /// The single route playback is on.
        case checkmark
        /// A room that can join the group, and one that's in it.
        case circle, checkedCircle
    }

    let title: String
    var subtitle: Text? = nil
    let symbol: String
    let mark: Mark
    /// 0...1, or `nil` where there's no level to set from here.
    let level: Double?
    var isMuted = false
    /// False while the list is moving: a touch that lands then only stops it.
    let listIsSettled: Bool
    let onTap: () -> Void
    let onLevel: (Double) -> Void
    /// A volume drag started (`true`) or ended (`false`).
    let onAdjusting: (Bool) -> Void

    @GestureState private var isTouching = false
    @State private var touch: Touch?
    @State private var width: CGFloat = 0

    private struct Touch: Equatable {
        let beganWhileScrolling: Bool
        var axis: Axis?
        var anchorX: CGFloat = 0
        var startLevel: Double = 0
    }

    /// How far a touch moves before it counts as a drag, and which way.
    /// Under the scroll view's own threshold, so a sideways drag is claimed
    /// before the list starts to move.
    private static let decisionDistance: CGFloat = 8
    private static let accessibilityStep = 0.05

    private var isAdjusting: Bool { touch?.axis == .horizontal }
    private var isSelected: Bool { mark == .checkmark || mark == .checkedCircle }

    /// 0 or 1 while a drag holds the level at that end, for the haptic.
    private var edge: Int? {
        guard isAdjusting, let level else { return nil }
        if level <= 0 { return 0 }
        if level >= 1 { return 1 }
        return nil
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let subtitle {
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            accessory
                .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background { track }
        .contentShape(.capsule)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scaleEffect(isAdjusting ? 1.02 : 1)
        .animation(.snappy(duration: 0.2), value: isAdjusting)
        .simultaneousGesture(drag)
        .onChange(of: isTouching) { _, touching in
            guard !touching else { return }
            // A touch that lifted has been through `onEnded` already. One
            // the system took away (the sheet closing, the list claiming
            // it) only resets the gesture state; finish it here, a turn
            // later so a normal end's `onEnded` always goes first.
            Task { @MainActor in
                guard !isTouching, let leftover = touch else { return }
                touch = nil
                if leftover.axis == .horizontal { onAdjusting(false) }
            }
        }
#if !os(visionOS)
        .sensoryFeedback(.impact(weight: .light), trigger: edge) { _, new in new != nil }
#endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onTap() }
        .accessibilityAdjustableAction { direction in
            guard let level else { return }
            switch direction {
            case .increment: onLevel(min(1, level + Self.accessibilityStep))
            case .decrement: onLevel(max(0, level - Self.accessibilityStep))
            @unknown default: break
            }
        }
    }

    // MARK: Drawing

    private var track: some View {
        Capsule()
            .fill(Color.primary.opacity(isSelected ? 0.14 : 0.06))
            .overlay(alignment: .leading) {
                if let level {
                    Rectangle()
                        .fill(Color.primary.opacity(fillOpacity))
                        .frame(width: width * min(1, max(0, level)))
                        // Follows the finger exactly while dragged; a level
                        // that arrives from the speaker glides there.
                        .animation(isAdjusting ? nil : .smooth, value: level)
                }
            }
            .clipShape(.capsule)
    }

    private var fillOpacity: Double {
        let base = isSelected ? 0.22 : 0.12
        return isMuted ? base / 2 : base
    }

    @ViewBuilder
    private var accessory: some View {
        if isAdjusting, let level {
            Text(level, format: .percent.precision(.fractionLength(0)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: level))
        } else {
            switch mark {
            case .empty:
                EmptyView()
            case .checkmark:
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
            case .circle:
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            case .checkedCircle:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let level {
            parts.append(level.formatted(.percent.precision(.fractionLength(0))))
        }
        if isMuted {
            parts.append(String(localized: "Muted"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged(dragChanged)
            .onEnded(dragEnded)
    }

    private func dragChanged(_ value: DragGesture.Value) {
        var current = touch ?? Touch(beganWhileScrolling: !listIsSettled)
        if current.axis == nil {
            let dx = value.translation.width
            let dy = value.translation.height
            if max(abs(dx), abs(dy)) >= Self.decisionDistance {
                if let level, !current.beganWhileScrolling, abs(dx) > abs(dy) {
                    current.axis = .horizontal
                    current.anchorX = dx
                    current.startLevel = level
                    onAdjusting(true)
                } else {
                    current.axis = .vertical
                }
            }
        }
        if current != touch {
            touch = current
        }
        guard current.axis == .horizontal, width > 0 else { return }
        let next = current.startLevel + (value.translation.width - current.anchorX) / width
        onLevel(min(1, max(0, next)))
    }

    private func dragEnded(_ value: DragGesture.Value) {
        let finished = touch
        touch = nil
        if finished?.axis == .horizontal {
            onAdjusting(false)
        } else if finished?.axis == nil, !(finished?.beganWhileScrolling ?? !listIsSettled) {
            // Never moved far enough to pick a way: a tap — unless it landed
            // on a list still moving, where all it did was stop it.
            onTap()
        }
    }
}

// MARK: - Room volume

/// Sends a room's level while its row is dragged: to the model at once, so
/// the fill keeps up with the finger, and to the speaker at most every
/// `interval`, always the latest level and never a repeat. Each request is a
/// SOAP round trip, and one per drag tick queued up behind the finger.
///
/// Holds the room's `isEditingVolume` until a moment after the last write —
/// the speaker reports the levels the drag passed through, and a poll's read
/// of one would pull the fill back under the finger. Then it re-takes the
/// group's volume snapshot, so a later group change keeps the new balance,
/// and reads the group's level for the player's slider.
///
/// Its tasks keep it alive past the sheet closing, so the hold is always let
/// go.
@MainActor
final class RoomVolumeWriter {
    private var pending: [String: (ip: String, volume: Int)] = [:]
    private var writers: [String: Task<Void, Never>] = [:]
    private var releases: [String: Task<Void, Never>] = [:]

    private static let interval: Duration = .milliseconds(80)
    private static let hold: Duration = .milliseconds(1500)

    /// `volume` is 0...100. A level the room already has does nothing: a
    /// drag reports the same level many times over, and the hold only
    /// starts with something to send.
    func set(_ room: Room, to volume: Double) {
        let level = min(100, max(0, volume.rounded()))
        guard room.volume != level else { return }
        releases.removeValue(forKey: room.id)?.cancel()
        if !room.isEditingVolume {
            room.isEditingVolume = true
        }
        // Turning a muted room up means hearing it, as the other volume
        // sliders do.
        if room.isMuted {
            room.isMuted = false
            let ip = room.ip
            Task { await SonosService.shared.setRoomMute(IP: ip, mute: false) }
        }
        room.volume = level
        pending[room.id] = (room.ip, Int(level))
        startWriting(room)
    }

    /// One write loop per room, while there's a level waiting. It hands the
    /// room to `release` once it runs dry.
    private func startWriting(_ room: Room) {
        let id = room.id
        guard writers[id] == nil else { return }
        writers[id] = Task {
            while let next = pending.removeValue(forKey: id) {
                await SonosService.shared.setDeviceVolume(ip: next.ip, volume: next.volume)
                try? await Task.sleep(for: Self.interval)
            }
            writers[id] = nil
            release(room)
        }
    }

    private func release(_ room: Room) {
        let id = room.id
        releases[id]?.cancel()
        releases[id] = Task {
            try? await Task.sleep(for: Self.hold)
            guard !Task.isCancelled else { return }
            releases[id] = nil
            room.isEditingVolume = false
            await settleGroupVolume(around: room)
        }
    }

    private func settleGroupVolume(around room: Room) async {
        let sonos = SonosService.shared
        guard let group = sonos.groups.first(where: { group in group.rooms.contains { $0.id == room.id } }) else { return }
        if group.rooms.count > 1 {
            await sonos.snapShotGroup(ip: group.ip)
        }
        if let volume = try? await sonos.getGroupVolume(ip: group.ip), !group.isEditingVolume, group.groupVolume != volume {
            group.groupVolume = volume
        }
    }
}

#Preview {
    Text("Player")
        .sheet(isPresented: .constant(true)) {
            PlayOnSheet()
        }
}
