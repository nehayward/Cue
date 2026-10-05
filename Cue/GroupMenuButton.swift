import SwiftUI
import SonosKit
import VibesDS

/// What regrouping `group` does: a room toggled in or out of it, every room
/// brought into it, or every other room let go.
///
/// Shared by `GroupMenuItems` and the Play On screen, so the two can't drift.
/// The rules mirror `GroupScreen`'s exactly: membership changes go through
/// `smartGroup` with the same diff, the last room can't leave its own group,
/// and when the change promotes a new coordinator the player follows it —
/// through the route when it points at this group, through the router
/// otherwise.
@MainActor
struct GroupMembership {
    let group: GroupRoom

    /// Off the singleton, not the environment: the route picker is hosted in
    /// the tab bar accessory, outside what `withEnvironments()` installs.
    private var sonosService: SonosService { .shared }

    var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }

    var allGrouped: Bool {
        let memberIDs = Set(group.rooms.map(\.id))
        let rooms = activeRooms
        return !rooms.isEmpty && rooms.allSatisfy { memberIDs.contains($0.id) }
    }

    var canUngroup: Bool { group.rooms.count > 1 }

    func isMember(_ room: Room) -> Bool {
        group.rooms.contains { $0.id == room.id }
    }

    /// A solo room is its own group — there's nothing to leave.
    func canToggle(_ room: Room) -> Bool {
        !(isMember(room) && group.rooms.count == 1)
    }

    /// One tap, one membership change: drop the room if it's in the group,
    /// add it if it isn't.
    func toggle(_ room: Room) {
        guard canToggle(room) else { return }
        HapticManager.shared.fireHaptic(.selection)
        let members = isMember(room)
            ? group.rooms.filter { $0.id != room.id }
            : group.rooms + [room]
        regroup(to: members)
    }

    func groupEverywhere() {
        HapticManager.shared.fireHaptic(.buttonPress)
        let rooms = activeRooms
        let coordinatorID = group.coordinatorID
        Task {
            // `speedGroup` may keep a group that's already playing and fold
            // this one into it; the player follows.
            guard let everywhere = await sonosService.speedGroup(rooms: rooms),
                  everywhere.coordinatorID != coordinatorID else { return }
            Self.follow(from: coordinatorID, to: everywhere.coordinatorID)
        }
    }

    func ungroupAll() {
        HapticManager.shared.fireHaptic(.buttonPress)
        regroup(to: [group.coordinatorRoom])
    }

    /// Lets every other room go, so playback carries on in `room` alone.
    ///
    /// In two steps when `room` isn't the coordinator: the others first,
    /// keeping the coordinator so playback stays put, then the coordinator,
    /// which hands playback to the one room left. `smartGroup` promotes the
    /// first room still there when the coordinator goes, so taking them all
    /// at once could promote a room the same call then drops.
    func playOnly(_ room: Room) {
        guard isMember(room), group.rooms.count > 1 else { return }
        HapticManager.shared.fireHaptic(.buttonPress)
        let original = group.rooms
        let coordinator = group.coordinatorRoom
        let coordinatorID = group.coordinatorID
        Task {
            if room.id == coordinatorID {
                _ = await sonosService.smartGroup(rooms: [room], oldRooms: original, to: group)
                return
            }
            if original.count > 2 {
                _ = await sonosService.smartGroup(rooms: [coordinator, room], oldRooms: original, to: group)
            }
            guard let newCoordinatorID = await sonosService.smartGroup(
                rooms: [room],
                oldRooms: [coordinator, room],
                to: group
            ) else { return }
            Self.follow(from: coordinatorID, to: newCoordinatorID)
        }
    }

    /// Same flow as `GroupScreen.addGroup`: `smartGroup` diffs `members`
    /// against the group's current rooms, and when the change removed the
    /// coordinator it returns the promoted one for the player to follow.
    private func regroup(to members: [Room]) {
        guard !members.isEmpty else { return }
        let current = group.rooms
        let coordinatorID = group.coordinatorID
        Task {
            guard let newCoordinatorID = await sonosService.smartGroup(rooms: members, oldRooms: current, to: group) else { return }
            Self.follow(from: coordinatorID, to: newCoordinatorID)
        }
    }

    /// The player the mini player opens follows the route, so the route is
    /// what moves to the promoted coordinator; the sidebar's player is
    /// reached through the router and moves with it.
    private static func follow(from coordinatorID: String, to newCoordinatorID: String) {
        if PlaybackRoute.shared.destination == .group(coordinatorID) {
            PlaybackRoute.shared.follow(groupID: newCoordinatorID)
        } else {
            Router.main.selectedID = newCoordinatorID
            Router.main.navigate(to: .player(groupID: newCoordinatorID))
        }
    }
}

/// The regroup rows: every active room as a toggle on `group`'s membership,
/// then Everywhere and Ungroup All. Used by `GroupMenuButton`'s
/// press-and-hold menu; what each row does is `GroupMembership`.
///
/// The rooms sit under a plain "Speakers" header rather than the group's
/// name: the group's own rooms are in the list already, so a solo group
/// would read its name twice in a row.
struct GroupMenuItems: View {
    let group: GroupRoom

    var body: some View {
        let membership = GroupMembership(group: group)
        Section("Speakers") {
            ForEach(membership.activeRooms) { room in
                // The binding is display-only; a tap always means "toggle
                // this room", and `toggle` owns what that does.
                Toggle(room.name, isOn: Binding(
                    get: { membership.isMember(room) },
                    set: { _ in membership.toggle(room) }
                ))
                .disabled(!membership.canToggle(room))
            }
        }
        Section {
            Button {
                membership.groupEverywhere()
            } label: {
                SwiftUI.Label("Everywhere", systemImage: "hifispeaker.2.fill")
            }
            .disabled(membership.allGrouped)

            Button {
                membership.ungroupAll()
            } label: {
                SwiftUI.Label("Ungroup All", systemImage: "hifispeaker.fill")
            }
            .disabled(!membership.canUngroup)
        }
    }
}

/// The group button, with a press-and-hold menu for quick regrouping.
///
/// A tap keeps the button's existing job — `openGroupScreen` presents the full
/// `GroupScreen` — while holding it shows `GroupMenuItems`, so adding or
/// dropping one speaker doesn't need the sheet at all.
struct GroupMenuButton<Label: View>: View {
    let group: GroupRoom
    /// The tap — presents the full group screen, exactly as the plain button did.
    let openGroupScreen: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            GroupMenuItems(group: group)
        } label: {
            label()
        } primaryAction: {
            openGroupScreen()
        }
    }
}

#Preview {
    GroupMenuButton(group: .garage) {
        print("open group screen")
    } label: {
        GroupIconView()
    }
    .environment(SonosService.shared)
}
