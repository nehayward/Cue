import SwiftUI
import SonosKit
import VibesDS

/// The regroup rows: every active room as a toggle on `group`'s membership,
/// then Everywhere and Ungroup All.
///
/// Shared by `GroupMenuButton` and the route picker, so the two can't drift.
/// The rows mirror `GroupScreen`'s semantics exactly: membership changes go
/// through `smartGroup` with the same diff, the last room can't leave its own
/// group, and when the change promotes a new coordinator the player follows
/// it — through the route when it points at this group, through the router
/// otherwise.
///
/// The rooms sit under a plain "Speakers" header rather than the group's
/// name: the group's own rooms are in the list already, so a solo group
/// would read its name twice in a row.
struct GroupMenuItems: View {
    /// Off the singleton, not the environment: the route picker hosts this in
    /// the tab bar accessory, outside what `withEnvironments()` installs.
    private var sonosService: SonosService { .shared }

    let group: GroupRoom

    private var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }

    private var allGrouped: Bool {
        let memberIDs = Set(group.rooms.map(\.id))
        return !activeRooms.isEmpty && activeRooms.allSatisfy { memberIDs.contains($0.id) }
    }

    var body: some View {
        Section("Speakers") {
            ForEach(activeRooms) { room in
                // The binding is display-only; a tap always means "toggle
                // this room", and `toggle` owns what that does.
                Toggle(room.name, isOn: Binding(
                    get: { isMember(room) },
                    set: { _ in toggle(room) }
                ))
                // A solo room is its own group — there's nothing to leave.
                .disabled(isMember(room) && group.rooms.count == 1)
            }
        }
        Section {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                let coordinatorID = group.coordinatorID
                Task {
                    // `speedGroup` may keep a group that's already playing
                    // and fold this one into it; the player follows.
                    guard let everywhere = await sonosService.speedGroup(rooms: activeRooms),
                          everywhere.coordinatorID != coordinatorID else { return }
                    follow(from: coordinatorID, to: everywhere.coordinatorID)
                }
            } label: {
                SwiftUI.Label("Everywhere", systemImage: "hifispeaker.2.fill")
            }
            .disabled(allGrouped)

            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                regroup(to: [group.coordinatorRoom])
            } label: {
                SwiftUI.Label("Ungroup All", systemImage: "hifispeaker.fill")
            }
            .disabled(group.rooms.count <= 1)
        }
    }

    private func isMember(_ room: Room) -> Bool {
        group.rooms.contains { $0.id == room.id }
    }

    /// One tap, one membership change: drop the room if it's in the group,
    /// add it if it isn't.
    private func toggle(_ room: Room) {
        HapticManager.shared.fireHaptic(.selection)
        let members = isMember(room)
            ? group.rooms.filter { $0.id != room.id }
            : group.rooms + [room]
        regroup(to: members)
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
            follow(from: coordinatorID, to: newCoordinatorID)
        }
    }

    /// The player the mini player opens follows the route, so the route is
    /// what moves to the promoted coordinator; the sidebar's player is
    /// reached through the router and moves with it.
    private func follow(from coordinatorID: String, to newCoordinatorID: String) {
        if PlaybackRoute.shared.destination == .group(coordinatorID) {
            PlaybackRoute.shared.follow(groupID: newCoordinatorID)
        } else {
            Router.main.selectedID = newCoordinatorID
            Router.main.navigate(to: .player(groupID: newCoordinatorID))
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
