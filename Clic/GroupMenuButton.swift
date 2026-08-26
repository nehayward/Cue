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
                    Toggle(isOn: membership(of: room)) {
                        Text(room.name)
                    }
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
                    setMembers(to: [group.coordinatorRoom])
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

    private func membership(of room: Room) -> Binding<Bool> {
        Binding {
            group.rooms.contains(where: { $0.id == room.id })
        } set: { include in
            HapticManager.shared.fireHaptic(.selection)
            var members = group.rooms
            if include {
                guard !members.contains(where: { $0.id == room.id }) else { return }
                members.append(room)
            } else {
                // The last room can't leave its own group — same guard as
                // `GroupScreen.addGroup`.
                guard members.count > 1 else { return }
                members.removeAll { $0.id == room.id }
            }
            setMembers(to: members)
        }
    }

    /// Same flow as `GroupScreen.addGroup`: `smartGroup` diffs against the
    /// current members, and if the change removed the coordinator the player
    /// follows the promoted one.
    private func setMembers(to rooms: [Room]) {
        let oldRooms = group.rooms
        Task {
            let newCoordinatorID = await sonosService.smartGroup(rooms: rooms, oldRooms: oldRooms, to: group)
            if let newCoordinatorID {
                Router.main.selectedID = newCoordinatorID
                Router.main.navigate(to: .player(groupID: newCoordinatorID))
            }
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
