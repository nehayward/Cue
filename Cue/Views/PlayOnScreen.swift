import Defaults
import SonosKit
import SwiftUI

/// Where playback goes, and how loud each place is: the full-screen cover
/// behind the Play On button while Sonos is on. It zooms out of the button,
/// over the cover's colours as the player draws them, and a pull down or the
/// close button puts it back.
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
/// pull that closes it. A tap that lands while the list is still moving only
/// stops it; it never regroups.
struct PlayOnScreen: View {
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
    /// True when every row fits above the buttons, so there's nothing to
    /// scroll and every drag up or down is the pull that closes it.
    @State private var listFits = true
    @State private var volumes = SpeakerVolumeWriter()

    private static let deviceRowID = "device"
    private static let allSpeakersRowID = "all speakers"

    private var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Outside the list, so a pull down on it always closes.
            PlayOnHeader()
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)

            roomList
        }
        .background { PlayOnBackdrop() }
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        // `basedOnSize` alone measures against the whole list, Everywhere /
        // Ungroup All included, so a list that fit above them still moved.
        .scrollDisabled(listFits || adjustingRowID != nil)
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
        // How much longer the rows are than the room they have above the
        // buttons; negative when there's room to spare.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let visible = geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            return geometry.contentSize.height - visible
        } action: { _, overflow in
            // Half a point for rounding.
            listFits = overflow <= 0.5
        }
        // A bar rather than a stack under the list, so the rows scroll under
        // it and the system softens the edge they pass under: the sign
        // there's more.
        .playOnBar(edge: .bottom) {
            if let group = route.group, showsGroupingBar {
                groupingButtons(GroupMembership(group: group))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Layout

    /// Everywhere and Ungroup All: on a speaker, with another room to group.
    private var showsGroupingBar: Bool {
        route.group != nil && activeRooms.count > 1
    }

    /// The group's own volume and mute, at the head of the rooms, whenever
    /// playback is on a speaker. With one room it repeats that room's level,
    /// but the row stays put as rooms join, and only its badge counts them.
    private var showsAllSpeakers: Bool {
        route.group != nil
    }

    // MARK: - Rows

    private var deviceRow: some View {
        let volume = DeviceVolume.shared
        return VolumeRouteRow(
            title: String(localized: "This Device"),
            icon: .symbol(Self.deviceSymbol),
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
            if let group = route.group, showsAllSpeakers {
                allSpeakersRow(group)
            }
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
            icon: .symbol(room.isSoundbar ? "tv.and.hifispeaker.fill" : "hifispeaker.fill"),
            mark: mark,
            level: room.volume / 100,
            isMuted: room.isMuted,
            listIsSettled: listIsSettled,
            onTap: { tap(room, membership: membership) },
            onLevel: { volumes.set(room, to: $0 * 100) },
            onAdjusting: { setAdjusting(room.id, $0) }
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

    /// The line under a room's name, for a room that isn't part of where
    /// playback is: what its own group is playing, or who it's grouped with.
    /// Those are what a tap on it would take over.
    private func note(for room: Room) -> Text? {
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

    private func groupingButtons(_ membership: GroupMembership) -> some View {
        HStack(spacing: 12) {
            Button {
                membership.groupEverywhere()
            } label: {
                Label {
                    Text("Everywhere")
                } icon: {
                    // Every room, counted the way All Speakers counts its own.
                    SpeakerCountIcon(count: membership.activeRooms.count, height: 18)
                }
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
    }

    /// Every room in the group at once: Mute All / Unmute All, then the
    /// group's volume as a row like the rooms', which moves them all and
    /// keeps the balance between them, then Sync, which levels them.
    private func allSpeakersRow(_ group: GroupRoom) -> some View {
        let isMuted = group.isMuted || group.rooms.allSatisfy(\.isMuted)
        let isFixed = group.coordinatorRoom.isOutputFixed
        let level = Int(group.groupVolume.rounded())
        let isLevel = group.rooms.allSatisfy { Int($0.volume.rounded()) == level }
        return HStack(spacing: 10) {
            Button {
                setAllMuted(!isMuted, in: group)
            } label: {
                // No symbol transition: on the Mac each animated swap costs
                // GPU memory (see CLAUDE.md).
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .glassButton()
            .accessibilityLabel(isMuted ? "Unmute All" : "Mute All")

            VolumeRouteRow(
                title: String(localized: "All Speakers"),
                subtitle: Text(group.nameWithCount),
                icon: .speakers(group.rooms.count),
                mark: .empty,
                // A fixed-output coordinator ignores volume: nothing to drag.
                level: isFixed ? nil : group.groupVolume / 100,
                isMuted: isMuted,
                listIsSettled: listIsSettled,
                onLevel: { volumes.set(group, to: $0 * 100) },
                onAdjusting: { setAdjusting(Self.allSpeakersRowID, $0) }
            )

            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                volumes.sync(group)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .glassButton()
            // Nothing to level when every room is already there.
            .disabled(isFixed || isLevel)
            .accessibilityLabel("Sync Volumes")
            .accessibilityHint("Sets every room to \(level) percent")
        }
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

    /// Sonos's group mute mutes or unmutes every room in it. Shown at once
    /// on the rooms too; the poll confirms it.
    private func setAllMuted(_ mute: Bool, in group: GroupRoom) {
        HapticManager.shared.fireHaptic(.selection)
        group.isMuted = mute
        for room in group.rooms where room.isMuted != mute {
            room.isMuted = mute
        }
        Task { await sonosService.setGroupMute(group: group, mute: mute) }
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

private extension View {
    /// A bar the list scrolls under. On iOS 26 the system softens the list's
    /// edge beneath it, the sign that there's more; before, a plain inset.
    @ViewBuilder
    func playOnBar<Content: View>(edge: VerticalEdge, @ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: 0, content: content)
        }
    }
}

// MARK: - Backdrop

/// The player's own backdrop — the cover's colours under a thin material —
/// for whatever plays where the route points, so the screen reads as part of
/// the player it came from. Plain when nothing is playing.
private struct PlayOnBackdrop: View {
    private var route: PlaybackRoute { .shared }

    var body: some View {
        ZStack {
            Color(.systemBackground)
            if let group = route.group {
                GroupPlayerBackgroundView(group: group)
            } else if let content = LocalPlaybackService.shared.nowPlayingDisplay {
                ZStack {
                    ArtworkMeshBackground(content: content)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    BlurView()
                }
                .scaleEffect(1.3)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
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

            // A pull down closes it too, but a full-screen cover wants a way
            // out you can see, and the Mac has no pull.
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

/// One row of the Play On screen: a destination that is also its own volume
/// slider, the way the system's AirPlay picker draws one.
///
/// A tap routes; a sideways drag sets the volume, through `SidewaysPan`,
/// which never starts on a drag up or down. Those go on to the list and the
/// pull that closes the screen untouched. The first version caught every
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
    /// A volume drag started (`true`) or ended (`false`).
    let onAdjusting: (Bool) -> Void

    /// The level when the volume drag began; `nil` when there isn't one.
    @State private var startLevel: Double?
    @State private var width: CGFloat = 0

    private static let accessibilityStep = 0.05

    private var isAdjusting: Bool { startLevel != nil }
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
            // Symbols strike one, rather than as a line of text.
            .overlay {
                if isMuted {
                    MutedSlash()
                }
            }
            .padding(6)
            .compositingGroup()
            .padding(-6)
            .opacity(isMuted ? 0.6 : 1)

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
        .contentShape(.contextMenuPreview, .capsule)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scaleEffect(isAdjusting ? 1.02 : 1)
        .animation(.snappy(duration: 0.2), value: isAdjusting)
        .onTapGesture {
            // A tap that only stopped the list moving isn't a choice.
            guard listIsSettled else { return }
            onTap?()
        }
        .gesture(
            SidewaysPan(
                isEnabled: level != nil,
                onBegan: beginAdjusting,
                onChanged: adjust,
                onEnded: endAdjusting
            )
        )
#if !os(visionOS)
        .sensoryFeedback(.impact(weight: .light), trigger: edge) { _, new in new != nil }
#endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(accessibilityTraits)
        .accessibilityAction { onTap?() }
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

    private var accessibilityTraits: AccessibilityTraits {
        guard onTap != nil else { return [] }
        return isSelected ? [.isButton, .isSelected] : .isButton
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
        onAdjusting(true)
    }

    /// `translation` is how far the finger has gone sideways since the drag
    /// began; the whole row's width is the whole range.
    private func adjust(_ translation: CGFloat) {
        guard let startLevel, width > 0 else { return }
        onLevel(min(1, max(0, startLevel + translation / width)))
    }

    private func endAdjusting() {
        guard startLevel != nil else { return }
        startLevel = nil
        onAdjusting(false)
    }
}

/// A room's speaker with a badge at its top right counting the rooms, cut
/// out of the speaker the way the system cuts a badge out of an app icon.
/// No badge for one: it's then just a speaker, like the rooms below it.
///
/// One compositing group, so the cuts go through to whatever is behind the
/// row: the speaker is cleared a little wider than the badge, and the count
/// is cleared out of the badge, which keeps it legible in light and dark.
private struct SpeakerCountIcon: View {
    let count: Int
    /// The speaker's height; the badge scales with it.
    var height: CGFloat = 22

    private var badgeHeight: CGFloat { (height * 0.6).rounded() }
    private var gap: CGFloat { max(1, height * 0.07) }

    /// Round for one digit, a capsule for two.
    private var badgeWidth: CGFloat { count > 9 ? badgeHeight + 6 : badgeHeight }

    var body: some View {
        Image(systemName: "hifispeaker.fill")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    ZStack {
                        Capsule()
                            .frame(width: badgeWidth + gap * 2, height: badgeHeight + gap * 2)
                            .blendMode(.destinationOut)
                        Capsule()
                            .frame(width: badgeWidth, height: badgeHeight)
                        Text(count, format: .number)
                            .font(.system(size: badgeHeight * 0.7, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .blendMode(.destinationOut)
                    }
                    // Centred just inside the speaker's corner.
                    .offset(x: (badgeWidth + gap * 2) / 2 - 1, y: 1 - (badgeHeight + gap * 2) / 2)
                }
            }
            // Room around the speaker inside the group, so the badge that
            // hangs past its corner is composited too, then given back.
            .padding(10)
            .compositingGroup()
            .padding(-10)
            .accessibilityHidden(true)
    }
}

/// The slash a muted row's icon is struck with, drawn the way SF Symbols
/// draw theirs: top left to bottom right, with a cut either side so it
/// stands clear of the glyph. Lives in the icon's compositing group, so the
/// cut goes through to the row behind.
private struct MutedSlash: View {
    var body: some View {
        ZStack {
            Capsule()
                .frame(width: 6, height: 32)
                .blendMode(.destinationOut)
            Capsule()
                .frame(width: 2.5, height: 30)
        }
        .rotationEffect(.degrees(-45))
        .accessibilityHidden(true)
    }
}

/// A pan that only ever starts sideways.
///
/// One that sets off up or down fails at once, so the list's scroll and the
/// pull that closes the screen get every vertical drag as if the row weren't
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

        /// The list's pan and the closing pull's: any other pan the touch could
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
/// Its tasks keep it alive past the screen closing, so the hold is always let
/// go.
@MainActor
final class SpeakerVolumeWriter {
    private var pending: [String: Int] = [:]
    private var writers: [String: Task<Void, Never>] = [:]
    private var releases: [String: Task<Void, Never>] = [:]

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
            room.isMuted = false
            Task { await SonosService.shared.setRoomMute(IP: ip, mute: false) }
        }
        room.volume = level
        write(Int(level), key: room.id) { volume in
            await SonosService.shared.setDeviceVolume(ip: ip, volume: volume)
        } drained: {
        } settle: { [weak room] in
            guard let room else { return }
            room.isEditingVolume = false
            await Self.settleGroupVolume(around: room)
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
            group.isMuted = false
            for room in group.rooms where room.isMuted {
                room.isMuted = false
            }
            Task { await SonosService.shared.setGroupMute(group: group, mute: false) }
        }
        group.groupVolume = level
        let ip = group.ip
        write(Int(level), key: "group:" + group.coordinatorID) { volume in
            await SonosService.shared.setGroupVolume(ip: ip, volume: volume)
        } drained: { [weak group] in
            // The rooms' rows follow whenever the finger rests, not only
            // after the hold.
            guard let group else { return }
            await SonosService.shared.updateRoomVolumes(for: group)
        } settle: { [weak group] in
            guard let group else { return }
            group.isEditingVolume = false
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
        drained: @escaping () async -> Void,
        settle: @escaping () async -> Void
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

    private func hold(_ key: String, then settle: @escaping () async -> Void) {
        releases[key]?.cancel()
        releases[key] = Task {
            try? await Task.sleep(for: Self.editingHold)
            guard !Task.isCancelled else { return }
            releases[key] = nil
            await settle()
        }
    }

    private static func settleGroupVolume(around room: Room) async {
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
        .fullScreenCover(isPresented: .constant(true)) {
            PlayOnScreen()
        }
}
