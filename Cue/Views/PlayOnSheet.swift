import Defaults
import SonosKit
import SwiftUI

/// Where playback goes, and how loud each place is: the sheet behind the Play
/// On button while Sonos is on. It zooms out of the button, one height
/// fitted to its rooms, and a pull down puts it back.
///
/// Laid out like the system's AirPlay picker: what's playing on top, then This
/// Device and every active room. Each row is its own volume slider — the fill
/// is the level, and a sideways drag anywhere on the row moves it — so a
/// group's rooms can be balanced from one place, and a room playing something
/// else can be turned down without leaving. A long press on a room mutes it
/// alone, or keeps playback there and lets the others go.
///
/// A tap is the route. On this device, tapping a room moves playback to the
/// group that room is in. On a speaker, the rooms are toggles on the group's
/// membership (`GroupMembership`, the same rules as the press-and-hold group
/// menu): tap to add one, tap again to drop it. This Device leaves the
/// speakers.
///
/// The rows sit in a scroll view, under a header that isn't part of it, and
/// a sideways drag is the only one a row takes (`SidewaysPan`): up and down
/// belong to the list and, from the header or the top of the list, to the
/// sheet's pull to dismiss. A tap that lands while the list is still moving
/// only stops it; it never regroups.
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
    /// True when every row fits above the buttons, so there's nothing to
    /// scroll and every drag up or down is the sheet's.
    @State private var listFits = false
    /// The parts the sheet's height adds up from: the header, the rows, the
    /// buttons' bar and the safe area under it. Each is measured on its own,
    /// with `onGeometryChange`, which reports the first value as well as
    /// every change. None depends on the sheet's height, so a measure taken
    /// mid-presentation, while the sheet is still zooming out of the button
    /// at some other size, can't throw the fit (it used to open full height).
    @State private var headerHeight: CGFloat = 0
    @State private var rowsHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    @State private var bottomInset: CGFloat = 0
    @State private var volumes = SpeakerVolumeWriter()
    /// Pulled up to the large detent rather than at its fitted height.
    @State private var isFullHeight = false
    /// The sheet's height once the rows have been measured; see `refit`.
    @State private var sheetHeight: CGFloat?

    private var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Outside the list, so a pull down on it is always the sheet's.
            PlayOnHeader()
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    headerHeight = $0
                    refit()
                }

            roomList
            groupBar
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: {
            bottomInset = $0
            refit()
        }
        // Opens fitted to the rooms, as the system's picker does, and a swipe
        // up still takes it to full height. The binding keeps it fitted as
        // the fit changes, unless it's been pulled up.
        .presentationDetents([fittedDetent, .large], selection: Binding(
            get: { isFullHeight ? .large : fittedDetent },
            set: { isFullHeight = $0 == .large }
        ))
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

    private var roomList: some View {
        ScrollView {
            VStack(spacing: 10) {
                deviceRow
                speakerRows
            }
            .animation(.smooth(duration: 0.35), value: expandedGroup?.coordinatorID)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                rowsHeight = $0
                refit()
            }
        }
        // Off outright when the rows fit, so every vertical drag is the
        // sheet's. A volume drag needs nothing here: the list's pan waits
        // for `SidewaysPan` to fail, so it can't scroll while one runs.
        .scrollDisabled(listFits)
        .scrollBounceBehavior(.basedOnSize)
        // With more rooms than fit, the indicator shows on open that the
        // list goes on; with nothing to scroll, nothing shows.
        .scrollIndicatorsFlash(onAppear: true)
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
        // While it scrolls, the rows fade out above the bar: the sign
        // there's more.
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: listFits ? 0 : 24)
            }
        }
    }

    /// Under the list rather than over it: rows passing beneath showed
    /// through its circles and the badges' cut-outs.
    @ViewBuilder
    private var groupBar: some View {
        if let group = expandedGroup {
            GroupBar(group: group, volumes: volumes, listIsSettled: listIsSettled)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    barHeight = $0
                    refit()
                }
                .transition(.opacity)
        }
    }

    // MARK: - Height

    /// The group's volume, Sync and Everywhere: once playback is on a speaker.
    private var showsGroupingBar: Bool {
        expandedGroup != nil
    }

    /// This device and the rows under it: All Speakers and every room on a
    /// speaker, a row per group elsewhere.
    private var rowCount: Int {
        1 + (activeRooms.isEmpty ? 1 : speakerItems.count)
    }

    /// What decides the height, as `FittedSheetHeights` files it.
    private var layout: String {
        "rows \(rowCount), buttons \(showsGroupingBar ? 1 : 0)"
    }

    private var fittedDetent: PresentationDetent {
        .height(sheetHeight ?? openingSheetHeight)
    }

    /// The height to open at: what this layout fitted to last time, so the
    /// sheet zooms out of the button at its size instead of changing size
    /// once it's up. A guess the first time.
    private var openingSheetHeight: CGFloat {
        min(FittedSheetHeights.height(for: layout) ?? estimatedSheetHeight, Self.tallestSheet)
    }

    /// The header, the rows and the buttons on a speaker, at the default
    /// text size.
    private var estimatedSheetHeight: CGFloat {
        let buttons: CGFloat = showsGroupingBar ? 96 : 0
        return min(106 + CGFloat(rowCount) * 68 + buttons, Self.tallestSheet)
    }

    /// Fits the sheet to its parts, once the rows are measured: up to about
    /// where the system's large sheet stops, and past that the list scrolls.
    private func refit() {
        guard rowsHeight > 0, headerHeight > 0 else { return }
        let bar = showsGroupingBar ? barHeight : 0
        // A point to spare, so rounding never leaves the list a hair too
        // long to sit still.
        let needed = headerHeight + rowsHeight + bar + bottomInset + 1
        listFits = needed <= Self.tallestSheet
        let target = min(max(needed, Self.shortestSheet), Self.tallestSheet)
        let current = sheetHeight ?? openingSheetHeight
        guard abs(target - current) > 0.5 else { return }
        // Grows with the rows as a group opens out into its rooms.
        withAnimation(.smooth(duration: 0.35)) {
            sheetHeight = target
        }
        FittedSheetHeights.remember(target, for: layout)
    }

    private static let shortestSheet: CGFloat = 240

    private static var tallestSheet: CGFloat {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return 640 }
        return window.bounds.height - window.safeAreaInsets.top - 16
    }

    // MARK: - Rows

    // Each row is its own view and reads its own room, so a level changing
    // (a drag tick, the poll) redraws that row, not the whole sheet.

    private var deviceRow: some View {
        DeviceRow(
            isCurrent: route.destination == .device,
            listIsSettled: listIsSettled,
            onSelect: { select(.device) }
        )
    }

    /// The group playback is on once it's settled there. Until then, and on
    /// this device, each group is one row: a tap takes the whole group, so
    /// the row says so, and it opens out into its rooms once the hand-off
    /// lands rather than the moment it's tapped.
    private var expandedGroup: GroupRoom? {
        route.isSwitching ? nil : route.group
    }

    /// The rows under This Device, in order. A collapsed group shares its
    /// coordinator's id, so it turns into that room's row and the other
    /// rooms spill out around it.
    private var speakerItems: [SpeakerItem] {
        let rooms = activeRooms
        if let group = expandedGroup {
            return rooms.map(SpeakerItem.room)
        }
        var items: [SpeakerItem] = []
        var seen = Set<String>()
        for room in rooms {
            guard let group = sonosService.groups.first(where: { $0.rooms.contains { $0.id == room.id } }) else {
                items.append(.room(room))
                continue
            }
            let members = rooms.filter { member in group.rooms.contains { $0.id == member.id } }
            if members.count > 1 {
                if seen.insert(group.coordinatorID).inserted {
                    items.append(.group(group, rooms: members))
                }
            } else {
                items.append(.room(room))
            }
        }
        return items
    }

    @ViewBuilder
    private var speakerRows: some View {
        if activeRooms.isEmpty {
            Text(sonosService.isSearching ? "Looking for speakers…" : "No speakers found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
        } else {
            let membership = expandedGroup.map { GroupMembership(group: $0) }
            ForEach(speakerItems) { item in
                switch item {
                case let .group(group, rooms):
                    GroupRow(
                        group: group,
                        rooms: rooms,
                        isCurrent: route.destination.groupID == group.coordinatorID,
                        volumes: volumes,
                        listIsSettled: listIsSettled,
                        onSelect: select
                    )
                    .transition(.opacity)
                case let .room(room):
                    RoomRow(
                        room: room,
                        membership: membership,
                        volumes: volumes,
                        listIsSettled: listIsSettled,
                        onSelect: select
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
        }
    }

    // MARK: - Actions

    private func select(_ target: PlayDestination) {
        guard target != route.destination else { return }
        if target == .device, !FeatureGate.shared.isAvailable(.onDevicePlayback) {
            // The paywall is a full-screen cover off the root, and can't go
            // up over this one: close it first.
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

    /// The monitor keeps every room's level current, but only while it runs;
    /// one read on open means no row starts out at a stale level.
    private func refreshRoomVolumes() async {
        let sonos = SonosService.shared
        for group in sonos.groups {
            await sonos.updateRoomVolumes(for: group)
        }
    }
}

// MARK: - The rows

/// This device, with its own volume while it's what the buttons move.
private struct DeviceRow: View {
    let isCurrent: Bool
    let listIsSettled: Bool
    let onSelect: () -> Void

    private var volume: DeviceVolume { .shared }

    var body: some View {
        VolumeRouteRow(
            title: String(localized: "This Device"),
            icon: .symbol(Self.symbol),
            mark: isCurrent ? .checkmark : .empty,
            // While a speaker holds the system volume, the device's own
            // level isn't the one the buttons move: no fill to drag.
            level: volume.isAvailable ? volume.level : nil,
            listIsSettled: listIsSettled,
            onTap: onSelect,
            onLevel: { volume.set($0) }
        )
    }

    private static var symbol: String {
#if os(visionOS)
        return "visionpro"
#elseif targetEnvironment(macCatalyst)
        return "laptopcomputer"
#else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
#endif
    }
}

/// The bar under the rooms once playback is on a speaker: Everywhere (a
/// toggle that groups every room, or ungroups them once they all are), the
/// group's volume, and Sync. A press on the volume mutes them all.
private struct GroupBar: View {
    let group: GroupRoom
    let volumes: SpeakerVolumeWriter
    let listIsSettled: Bool

    var body: some View {
        let membership = GroupMembership(group: group)
        let isEverywhere = membership.allGrouped
        let isMuted = group.isMuted || group.rooms.allSatisfy(\.isMuted)
        let isFixed = group.coordinatorRoom.isOutputFixed
        let level = Int(group.groupVolume.rounded())
        let isLevel = group.rooms.allSatisfy { Int($0.volume.rounded()) == level }
        HStack(alignment: .barCircleCenter, spacing: 12) {
            if membership.activeRooms.count > 1 {
                BarCircleButton(title: isEverywhere ? "Ungroup All" : "Everywhere", isOn: isEverywhere) {
                    if isEverywhere {
                        membership.ungroupAll()
                    } else {
                        membership.groupEverywhere()
                    }
                } icon: {
                    // Every room, counted the way the volume counts its own.
                    SpeakerCountIcon(
                        count: membership.activeRooms.count,
                        height: 22,
                        badge: isEverywhere ? .white : .accentColor
                    )
                }
                .disabled(isEverywhere && !membership.canUngroup)
                .accessibilityLabel("Everywhere")
                .accessibilityValue(isEverywhere ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
            }

            VolumeRouteRow(
                title: String(localized: "All Speakers"),
                subtitle: Text(group.nameWithCount),
                icon: .speakers(group.rooms.count),
                mark: .empty,
                // A fixed-output coordinator ignores volume: nothing to drag.
                level: isFixed ? nil : group.groupVolume / 100,
                isMuted: isMuted,
                listIsSettled: listIsSettled,
                onLevel: { volumes.set(group, to: $0 * 100) }
            )
            .alignmentGuide(.barCircleCenter) { $0[VerticalAlignment.center] }
            .contextMenu {
                Button {
                    setAllMuted(!isMuted)
                } label: {
                    Label(
                        isMuted ? "Unmute All" : "Mute All",
                        systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                }
            }
            .accessibilityAction(named: isMuted ? "Unmute All" : "Mute All") {
                setAllMuted(!isMuted)
            }

            BarCircleButton(title: "Sync", isOn: false) {
                HapticManager.shared.fireHaptic(.buttonPress)
                volumes.sync(group)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3.weight(.semibold))
            }
            // Nothing to level when every room is already there.
            .disabled(isFixed || isLevel)
            .accessibilityLabel("Sync Volumes")
            .accessibilityHint("Sets every room to \(level) percent")
        }
    }

    /// Sonos's group mute mutes or unmutes every room in it. Shown at once
    /// on the rooms too; the poll confirms it.
    private func setAllMuted(_ mute: Bool) {
        HapticManager.shared.fireHaptic(.selection)
        group.holdMute(mute)
        for room in group.rooms where room.isMuted != mute {
            room.holdMute(mute)
        }
        Task { await SonosService.shared.setGroupMute(group: group, mute: mute) }
    }
}

/// A round button with its name underneath, filled with the tint while on.
private struct BarCircleButton<Icon: View>: View {
    let title: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon()
                    .frame(width: 56, height: 56)
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .background {
                        Circle()
                            .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                    }
                    .opacity(isEnabled ? 1 : 0.4)
                    .alignmentGuide(.barCircleCenter) { $0[VerticalAlignment.center] }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private extension VerticalAlignment {
    /// Lines the bar's circles up with the middle of the volume, their
    /// names hanging below.
    enum BarCircleCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let barCircleCenter = VerticalAlignment(BarCircleCenter.self)
}

/// What a row under This Device stands for.
private enum SpeakerItem: Identifiable {
    /// Two or more rooms grouped together, shown as one until playback
    /// settles on them.
    case group(GroupRoom, rooms: [Room])
    case room(Room)

    var id: String {
        switch self {
        case let .group(group, _):
            group.coordinatorID
        case let .room(room):
            room.id
        }
    }
}

/// A group of rooms as one destination: a tap takes the whole group, a
/// drag sets its volume, and the line under it says what it's playing.
private struct GroupRow: View {
    let group: GroupRoom
    /// Its active rooms.
    let rooms: [Room]
    /// Playback is on its way here.
    let isCurrent: Bool
    let volumes: SpeakerVolumeWriter
    let listIsSettled: Bool
    let onSelect: (PlayDestination) -> Void

    var body: some View {
        VolumeRouteRow(
            title: group.nameWithCount,
            subtitle: GroupNote.text(for: group) ?? Text(rooms.map(\.name).formatted(.list(type: .and))),
            icon: .speakers(rooms.count),
            mark: isCurrent ? .checkmark : .empty,
            // A fixed-output coordinator ignores volume: nothing to drag.
            level: group.coordinatorRoom.isOutputFixed ? nil : level / 100,
            isMuted: group.isMuted || rooms.allSatisfy(\.isMuted),
            listIsSettled: listIsSettled,
            onTap: { onSelect(.group(group.coordinatorID)) },
            onLevel: { volumes.set(group, to: $0 * 100) }
        )
    }

    /// The group's own level while it's being set; otherwise the rooms'
    /// average, which the sheet reads fresh on open — a group playback
    /// isn't on may not have had its own level read.
    private var level: Double {
        guard !group.isEditingVolume, !rooms.isEmpty else { return group.groupVolume }
        return rooms.map(\.volume).reduce(0, +) / Double(rooms.count)
    }
}

/// The line under a room or group playback isn't on: what it's playing,
/// or what it has paused.
private enum GroupNote {
    @MainActor
    static func text(for group: GroupRoom) -> Text? {
        let track = group.coordinatorRoom.track
        guard !track.isEmpty else { return nil }
        let symbol = group.coordinatorRoom.isPlaying ? "play.fill" : "pause.fill"
        return Text("\(Image(systemName: symbol)) \(track.song)")
    }
}

/// One room: a tap routes there or, on a speaker, adds or drops it; a long
/// press mutes it alone, or keeps playback there and lets the others go.
private struct RoomRow: View {
    let room: Room
    /// The group playback is on, or `nil` on this device.
    let membership: GroupMembership?
    let volumes: SpeakerVolumeWriter
    let listIsSettled: Bool
    let onSelect: (PlayDestination) -> Void

    private var sonosService: SonosService { .shared }

    var body: some View {
        VolumeRouteRow(
            title: room.name,
            subtitle: note,
            icon: .symbol(room.isSoundbar ? "tv.and.hifispeaker.fill" : "hifispeaker.fill"),
            mark: mark,
            level: room.volume / 100,
            isMuted: room.isMuted,
            listIsSettled: listIsSettled,
            onTap: tap,
            onLevel: { volumes.set(room, to: $0 * 100) }
        )
        .contextMenu {
            Button {
                HapticManager.shared.fireHaptic(.selection)
                let mute = !room.isMuted
                Task { await sonosService.setRoomMute(room: room, mute: mute) }
            } label: {
                Label(
                    room.isMuted ? "Unmute" : "Mute",
                    systemImage: room.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
            }
            if let membership, membership.isMember(room), membership.group.rooms.count > 1 {
                Button {
                    membership.playOnly(room)
                } label: {
                    Label("Play Only Here", systemImage: "hifispeaker.fill")
                }
            }
        }
    }

    private var mark: VolumeRouteRow.Mark {
        guard let membership else { return .empty }
        return membership.isMember(room) ? .checkedCircle : .circle
    }

    /// The group the room is in now, which may not be the one playback is on.
    private var ownGroup: GroupRoom? {
        sonosService.groups.first { group in group.rooms.contains { $0.id == room.id } }
    }

    /// The line under the name, for a room that isn't part of where playback
    /// is: what its own group is playing, or who it's grouped with. Those are
    /// what a tap on it would take over.
    private var note: Text? {
        guard let group = ownGroup, group.coordinatorID != membership?.group.coordinatorID else { return nil }
        if let note = GroupNote.text(for: group) {
            return note
        }
        let others = group.rooms.filter { $0.id != room.id }.map(\.name)
        guard !others.isEmpty else { return nil }
        return Text("With \(others.formatted(.list(type: .and)))")
    }

    private func tap() {
        if let membership {
            membership.toggle(room)
        } else if let group = ownGroup {
            onSelect(.group(group.coordinatorID))
        }
    }
}

/// The Play On sheet's fitted heights, by layout (`PlayOnSheet.layout`),
/// kept across launches. The rows are only measured once the sheet is up,
/// and a sheet that changed size then looked like it had stumbled out of
/// the button.
private enum FittedSheetHeights {
    private static var key: String { AppStorageKeys.playOnSheetHeights }

    static func height(for layout: String) -> CGFloat? {
        guard let stored = UserDefaults.standard.dictionary(forKey: key)?[layout] as? Double else { return nil }
        return CGFloat(stored)
    }

    static func remember(_ height: CGFloat, for layout: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        let value = Double(height)
        guard all[layout] != value else { return }
        all[layout] = value
        UserDefaults.standard.set(all, forKey: key)
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
            // A Mac sheet has no pull to close it, and a click outside
            // doesn't either.
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonBorderShape(.circle)
            .glassButton()
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
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
/// A tap routes; a sideways drag sets the volume, through `SidewaysPan`,
/// which never starts on a drag up or down. Those go on to the list and the
/// sheet's pull to dismiss untouched. The first version caught every
/// touch the moment it landed, with a SwiftUI drag, and a pull down on the
/// rows closed nothing.
struct VolumeRouteRow: View {
    enum Icon {
        case symbol(String)
        /// A speaker with a badge counting the rooms it stands for, shown
        /// once there's more than one.
        case speakers(Int)
    }

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
    let icon: Icon
    let mark: Mark
    /// 0...1, or `nil` where there's no level to set from here.
    let level: Double?
    var isMuted = false
    /// False while the list is moving: a touch that lands then only stops it.
    let listIsSettled: Bool
    /// `nil` for a row that's only a volume, with nowhere to route to.
    var onTap: (() -> Void)? = nil
    let onLevel: (Double) -> Void

    /// The level when the volume drag began; `nil` when there isn't one.
    @State private var startLevel: Double?
    @State private var width: CGFloat = 0

    private static let accessibilityStep = 0.05

    private var isAdjusting: Bool { startLevel != nil }
    private var isSelected: Bool { mark == .checkmark || mark == .checkedCircle }

    /// The percent a drag last ticked at. A plain reference, not state:
    /// it changes every tick and nothing draws from it.
    @State private var lastTick = TickMark()

    /// Steps of the drag that each get a tick: one per percent, the speaker's
    /// own unit of volume.
    private static let ticks = 100.0

    var body: some View {
        Group {
            if let onTap {
                // A button, for its pressed look, keyboard focus on iPad and
                // the Mac, the pointer's hover, and the button VoiceOver
                // reads. A sideways drag can't also press it: `SidewaysPan`
                // cancels the touch the moment it begins.
                Button {
                    // A tap that only stopped the list moving isn't a choice.
                    guard listIsSettled else { return }
                    onTap()
                } label: {
                    content
                }
                .buttonStyle(RouteRowButtonStyle())
            } else {
                content
            }
        }
        .contentShape(.contextMenuPreview, .capsule)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scaleEffect(isAdjusting ? 1.02 : 1)
        .animation(.snappy(duration: 0.2), value: isAdjusting)
        .gesture(
            SidewaysPan(
                isEnabled: level != nil,
                onBegan: beginAdjusting,
                onChanged: adjust,
                onEnded: endAdjusting
            )
        )
        // One element: the name (and the line under it) as the label, the
        // button's trait and tap from the button itself.
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAdjustableAction { direction in
            guard let level else { return }
            switch direction {
            case .increment: onLevel(min(1, level + Self.accessibilityStep))
            case .decrement: onLevel(max(0, level - Self.accessibilityStep))
            @unknown default: break
            }
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            // One box for every row's icon, so the names line up and the
            // wide TV glyph doesn't run into its name.
            Group {
                switch icon {
                case let .symbol(name):
                    Image(systemName: name)
                        .resizable()
                        .scaledToFit()
                case let .speakers(count):
                    SpeakerCountIcon(count: count)
                }
            }
            .frame(width: 30, height: 24)
            // Muted reads on the speaker itself, struck through the way SF
            // Symbols strike one, rather than as a line of text: a gap cut
            // either side of the slash, then the slash.
            //
            // Both are drawn as far as `slash` says, 0 to 1 from the top
            // left, so muting draws the slash on and unmuting takes it back.
            // The mask reaches past the icon, so a count badge that hangs
            // past its corner isn't clipped.
            .mask {
                SlashCut(progress: isMuted ? 1 : 0).fill(style: FillStyle(eoFill: true))
            }
            .overlay {
                SlashLine(progress: isMuted ? 1 : 0)
            }
            // Dimmed as well, with the system's tertiary style rather than
            // an opacity: on the glass sheet a faded white icon still came
            // out at full white, while the hierarchical styles are drawn
            // with the glass's own vibrancy.
            .foregroundStyle(isMuted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .animation(.smooth(duration: 0.3), value: isMuted)
            // Said in the value instead ("Muted").
            .accessibilityHidden(true)

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

            // Said in the value and the selected trait instead.
            accessory
                .frame(minWidth: 28, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background { track }
        // The whole row takes a touch, not just the capsule: the rounded
        // ends left their corners dead, and a tap there did nothing.
        .contentShape(.rect)
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

    private func beginAdjusting() {
        guard let level else { return }
        startLevel = level
        lastTick.value = Int((level * Self.ticks).rounded())
        VolumeHaptics.prepare()
    }

    /// `translation` is how far the finger has gone sideways since the drag
    /// began; the whole row's width is the whole range.
    ///
    /// The haptics fire from here, off the drag itself, rather than from a
    /// `sensoryFeedback` watching the level: that waited on the row to
    /// redraw with the speaker's level, and skipped steps a fast drag passed.
    private func adjust(_ translation: CGFloat) {
        guard let startLevel, width > 0 else { return }
        let next = min(1, max(0, startLevel + translation / width))
        let tick = Int((next * Self.ticks).rounded())
        if tick != lastTick.value {
            lastTick.value = tick
            // A firmer bump at either end, a tick on the way.
            if next <= 0 || next >= 1 {
                VolumeHaptics.edge()
            } else {
                VolumeHaptics.tick()
            }
        }
        onLevel(next)
    }

    private func endAdjusting() {
        startLevel = nil
    }
}

/// Holds the last ticked step across a drag's redraws without causing any.
private final class TickMark {
    var value: Int?
}

/// The volume drag's haptics: a light tick per step, a firmer bump at
/// either end. One shared pair of generators, prepared when a drag begins.
@MainActor
private enum VolumeHaptics {
#if !os(visionOS)
    private static let ticker = UISelectionFeedbackGenerator()
    private static let bumper = UIImpactFeedbackGenerator(style: .medium)
#endif

    static func prepare() {
#if !os(visionOS)
        ticker.prepare()
        bumper.prepare()
#endif
    }

    static func tick() {
#if !os(visionOS)
        ticker.selectionChanged()
        ticker.prepare()
#endif
    }

    static func edge() {
#if !os(visionOS)
        bumper.impactOccurred()
        bumper.prepare()
#endif
    }
}

/// A route row's pressed look: it gives a little under the finger, and the
/// pointer lights it on iPad and the Mac.
private struct RouteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            // Hit-tested outside the scale, so the row doesn't shrink out
            // from under a finger near its edge: one that landed in the
            // outer few points was outside by the time it lifted, and the
            // tap was lost.
            .contentShape(.rect)
            .contentShape(.hoverEffect, .capsule)
            .hoverEffect(.highlight)
    }
}

/// A room's speaker with a badge at its top right counting the rooms, cut
/// out of the speaker the way the system cuts a badge out of an app icon.
/// No badge for one: it's then just a speaker, like the rooms below it.
///
/// The cuts are masks, not blends: an even-odd path over the speaker with a
/// hole a little wider than the badge, then the badge, the accent with its
/// count masked out of it so whatever is behind the row shows through.
/// Blending them out (`destinationOut`) only erased what shared their
/// compositing group, and the overlay and offset the badge needs put it in
/// a group of its own: the hole never cut through.
private struct SpeakerCountIcon: View {
    let count: Int
    /// The speaker's height; the badge scales with it.
    var height: CGFloat = 22
    /// White on a circle already filled with the accent.
    var badge: Color = .accentColor

    private var badgeHeight: CGFloat { (height * 0.68).rounded() }
    private var gap: CGFloat { max(1, height * 0.07) }

    /// Round for one digit, a capsule for two.
    private var badgeWidth: CGFloat { count > 9 ? badgeHeight + 6 : badgeHeight }

    var body: some View {
        Image(systemName: "hifispeaker.fill")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .mask {
                if count > 1 {
                    BadgeCut(size: CGSize(width: badgeWidth + gap * 2, height: badgeHeight + gap * 2))
                        .fill(style: FillStyle(eoFill: true))
                } else {
                    Rectangle()
                }
            }
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Capsule()
                        .fill(badge)
                        .frame(width: badgeWidth, height: badgeHeight)
                        // The count cut out: white keeps the badge, the
                        // black digits take it away.
                        .mask {
                            ZStack {
                                Color.white
                                Text(count, format: .number)
                                    .font(.system(size: badgeHeight * 0.72, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.black)
                            }
                            .compositingGroup()
                            .luminanceToAlpha()
                        }
                        // Centred just inside the speaker's corner, where
                        // `BadgeCut` makes its hole.
                        .offset(x: badgeWidth / 2 - 1, y: 1 - badgeHeight / 2)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Everything around a view, less a capsule of `size` centred just inside its
/// top right corner: filled even-odd, a mask that leaves a hole there.
private struct BadgeCut: Shape {
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -12, dy: -12))
        let hole = CGRect(
            x: rect.maxX - 1 - size.width / 2,
            y: rect.minY + 1 - size.height / 2,
            width: size.width,
            height: size.height
        )
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: size.height / 2, height: size.height / 2))
        return path
    }
}

/// Everything around a view, less a band through its middle from top left to
/// bottom right, as far along as `progress`: filled even-odd, the gap either
/// side of a muted icon's slash. Nothing cut at 0.
private struct SlashCut: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -12, dy: -12))
        guard progress > 0 else { return path }
        let band = CGRect(x: rect.midX - 3, y: rect.midY - 16, width: 6, height: 32 * progress)
        path.addRoundedRect(in: band, cornerSize: CGSize(width: 3, height: 3), transform: SlashLine.turn(in: rect))
        return path
    }
}

/// A muted icon's slash, from top left to bottom right, as far along as
/// `progress`, in the gap `SlashCut` makes for it.
private struct SlashLine: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard progress > 0 else { return Path() }
        let line = CGRect(x: rect.midX - 1.25, y: rect.midY - 15, width: 2.5, height: 30 * progress)
        var path = Path()
        path.addRoundedRect(in: line, cornerSize: CGSize(width: 1.25, height: 1.25), transform: Self.turn(in: rect))
        return path
    }

    /// A vertical band through the middle, turned to run top left to bottom
    /// right; its top end lands top left.
    static func turn(in rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: -.pi / 4)
            .translatedBy(x: -rect.midX, y: -rect.midY)
    }
}

/// A pan that only ever starts sideways.
///
/// One that sets off up or down fails at once, so the list's scroll and the
/// sheet's pull to dismiss get every vertical drag as if the row weren't
/// there. Their pans wait for it to fail, the few points it takes to tell,
/// so a sideways drag is never a scroll or a dismiss as well. UIKit rather
/// than a SwiftUI drag: only a recognizer can decline to begin, where a
/// SwiftUI gesture takes the touch first and decides after.
struct SidewaysPan: UIGestureRecognizerRepresentable {
    var isEnabled = true
    let onBegan: () -> Void
    /// Points moved sideways since it began.
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            // Measured from here, not from where the finger landed: the few
            // points it took to tell the direction shouldn't jump the level.
            recognizer.setTranslation(.zero, in: recognizer.view)
            onBegan()
        case .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let moved = pan.translation(in: pan.view)
            let motion = moved == .zero ? pan.velocity(in: pan.view) : moved
            return abs(motion.x) > abs(motion.y)
        }

        /// The list's pan and the sheet's: any other pan the touch could
        /// start.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            other is UIPanGestureRecognizer && other !== recognizer
        }
    }
}

// MARK: - Volume

/// Sends a room's or a group's level while its row is dragged: to the model
/// at once, so the fill keeps up with the finger, and to the speaker at most
/// every `interval`, always the latest level and never a repeat. Each request
/// is a SOAP round trip, and one per drag tick queued up behind the finger.
///
/// Holds `isEditingVolume` until a moment after the last write — the speaker
/// reports the levels the drag passed through, and a poll's read of one would
/// pull the fill back under the finger. Then it settles what the change moved
/// elsewhere: a room's change moves its group's level, so the group's volume
/// snapshot is taken again (a later group change keeps the new balance) and
/// its level read for the player's slider; a group's change moves every
/// room, so their levels are read again.
///
/// Its tasks keep it alive past the sheet closing, so the hold is always let
/// go.
@MainActor
final class SpeakerVolumeWriter {
    private var pending: [String: Int] = [:]
    private var writers: [String: Task<Void, Never>] = [:]
    private var releases: [String: Task<Void, Never>] = [:]

    /// Each group's level and its rooms' when a drag of the group began, so
    /// the rooms' rows can follow it in proportion. Kept until the hold
    /// ends, so a drag picked up again goes on from the same start.
    private var groupDragStarts: [String: (level: Double, rooms: [String: Double])] = [:]

    private static let interval: Duration = .milliseconds(80)
    private static let editingHold: Duration = .milliseconds(1500)

    /// `volume` is 0...100. A level the room already has does nothing: a
    /// drag reports the same level many times over, and the hold only
    /// starts with something to send.
    func set(_ room: Room, to volume: Double, unmuting: Bool = true) {
        let level = Self.level(volume)
        guard room.volume != level else { return }
        if !room.isEditingVolume {
            room.isEditingVolume = true
        }
        let ip = room.ip
        // Turning a muted room up means hearing it, as the other volume
        // sliders do.
        if unmuting, room.isMuted {
            room.holdMute(false)
            Task { await SonosService.shared.setRoomMute(IP: ip, mute: false) }
        }
        room.volume = level
        // All Speakers follows at once: Sonos's group volume is its rooms'
        // average. Held against the poll, like the room, until the speaker
        // says what it made of it.
        if let group = Self.group(of: room) {
            if !group.isEditingVolume {
                group.isEditingVolume = true
            }
            let average = (group.rooms.map(\.volume).reduce(0, +) / Double(max(1, group.rooms.count))).rounded()
            if group.groupVolume != average {
                group.groupVolume = average
            }
        }
        write(Int(level), key: room.id) { volume in
            await SonosService.shared.setDeviceVolume(ip: ip, volume: volume)
        } drained: {
        } settle: { [weak self, weak room] in
            guard let self, let room else { return }
            room.isEditingVolume = false
            await settleGroupVolume(around: room)
        }
    }

    /// `volume` is 0...100; the speaker spreads it over the rooms in
    /// proportion, as the player's group slider does.
    func set(_ group: GroupRoom, to volume: Double) {
        let level = Self.level(volume)
        guard group.groupVolume != level else { return }
        if !group.isEditingVolume {
            group.isEditingVolume = true
        }
        if group.isMuted || group.rooms.contains(where: \.isMuted) {
            group.holdMute(false)
            for room in group.rooms where room.isMuted {
                room.holdMute(false)
            }
            Task { await SonosService.shared.setGroupMute(group: group, mute: false) }
        }
        let key = "group:" + group.coordinatorID
        let start = groupDragStarts[key] ?? (
            level: group.groupVolume,
            rooms: Dictionary(group.rooms.map { ($0.id, $0.volume) }, uniquingKeysWith: { first, _ in first })
        )
        groupDragStarts[key] = start
        group.groupVolume = level
        // The rooms follow at once, in proportion from where they were, as
        // the speaker moves them; held against the poll until the speaker's
        // own levels are read after the hold.
        for room in group.rooms {
            let from = start.rooms[room.id] ?? room.volume
            let estimate = Self.level(start.level > 0 ? from * level / start.level : level)
            if !room.isEditingVolume {
                room.isEditingVolume = true
            }
            if room.volume != estimate {
                room.volume = estimate
            }
        }
        let ip = group.ip
        write(Int(level), key: key) { volume in
            await SonosService.shared.setGroupVolume(ip: ip, volume: volume)
        } drained: {
        } settle: { [weak self, weak group] in
            guard let self, let group else { return }
            groupDragStarts[key] = nil
            group.isEditingVolume = false
            for room in group.rooms {
                room.isEditingVolume = false
            }
            await SonosService.shared.updateRoomVolumes(for: group)
        }
    }

    /// Sets every room in the group to the group's level — Sonos's group
    /// volume is the rooms' average, so the group sounds about as loud
    /// afterwards, only evenly. Mutes are left as they are: it's a level,
    /// not a turn up. The same path as a drag, so each room holds its new
    /// level against the poll and the group's snapshot is taken again.
    func sync(_ group: GroupRoom) {
        let level = group.groupVolume
        for room in group.rooms {
            set(room, to: level, unmuting: false)
        }
    }

    private static func level(_ volume: Double) -> Double {
        min(100, max(0, volume.rounded()))
    }

    /// One write loop per speaker, while there's a level waiting. It hands
    /// the speaker to the hold once it runs dry.
    private func write(
        _ volume: Int,
        key: String,
        send: @escaping (Int) async -> Void,
        drained: @escaping @MainActor () async -> Void,
        settle: @escaping @MainActor () async -> Void
    ) {
        releases.removeValue(forKey: key)?.cancel()
        pending[key] = volume
        guard writers[key] == nil else { return }
        writers[key] = Task {
            while let next = pending.removeValue(forKey: key) {
                await send(next)
                try? await Task.sleep(for: Self.interval)
            }
            writers[key] = nil
            hold(key, then: settle)
            await drained()
        }
    }

    private func hold(_ key: String, then settle: @escaping @MainActor () async -> Void) {
        releases[key]?.cancel()
        releases[key] = Task {
            try? await Task.sleep(for: Self.editingHold)
            guard !Task.isCancelled else { return }
            releases[key] = nil
            await settle()
        }
    }

    private static func group(of room: Room) -> GroupRoom? {
        SonosService.shared.groups.first { group in group.rooms.contains { $0.id == room.id } }
    }

    /// After a room's hold: re-takes the group's snapshot, so a later group
    /// change keeps the new balance, and once no room in it is still being
    /// set (and the group isn't being dragged itself), lets the speaker's
    /// own group level replace the average shown meanwhile.
    private func settleGroupVolume(around room: Room) async {
        let sonos = SonosService.shared
        guard let group = Self.group(of: room) else { return }
        if group.rooms.count > 1 {
            await sonos.snapShotGroup(ip: group.ip)
        }
        guard !group.rooms.contains(where: \.isEditingVolume),
              groupDragStarts["group:" + group.coordinatorID] == nil else { return }
        if let volume = try? await sonos.getGroupVolume(ip: group.ip), group.groupVolume != volume {
            group.groupVolume = volume
        }
        group.isEditingVolume = false
    }
}

#Preview {
    Text("Player")
        .sheet(isPresented: .constant(true)) {
            PlayOnSheet()
        }
}
