import SwiftUI
import SonosKit
import VibesDS

/// The group button, with a press-and-hold menu for quick regrouping.
///
/// A tap keeps the button's existing job — `openGroupScreen` presents the full
/// `GroupScreen` — while holding it lists the active rooms as toggles, so
/// adding or dropping one speaker doesn't need the sheet at all. The menu
/// mirrors `GroupScreen`'s semantics exactly: membership changes go through
/// `smartGroup` with the same diff, the last room can't leave its own group,
/// and when the change promotes a new coordinator the player follows it.
struct GroupMenuButton<Label: View>: View {
    @Environment(SonosService.self) private var sonosService

    let group: GroupRoom
    /// The tap — presents the full group screen, exactly as the plain button did.
    let openGroupScreen: () -> Void
    @ViewBuilder let label: () -> Label

    private var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }

    private var allGrouped: Bool {
        let memberIDs = Set(group.rooms.map(\.id))
        return !activeRooms.isEmpty && activeRooms.allSatisfy { memberIDs.contains($0.id) }
    }

    var body: some View {
        Menu {
            Section(group.nameWithCount) {
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
                    Task { _ = await sonosService.speedGroup(rooms: activeRooms) }
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
        } label: {
            label()
        } primaryAction: {
            openGroupScreen()
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
        Task {
            guard let newCoordinatorID = await sonosService.smartGroup(rooms: members, oldRooms: current, to: group) else { return }
            Router.main.selectedID = newCoordinatorID
            Router.main.navigate(to: .player(groupID: newCoordinatorID))
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
