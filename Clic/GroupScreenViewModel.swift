import SonosKit
import Observation

@Observable
final class GroupScreenViewModel {
    var group: GroupRoom
    var selections: Set<String>
    @ObservationIgnored var sonosService: SonosService

    init(groupCoordinatorID: String, sonosService: SonosService) {
        self.sonosService = sonosService
        self.group = sonosService.sorted.first(where: { $0.coordinatorID == groupCoordinatorID })!
        guard let group = sonosService.sorted.first(where: { $0.coordinatorID == groupCoordinatorID }) else {
            selections = []
            return
        }
        self.selections = Set(group.rooms.filter { $0.id != group.coordinatorID }.map { $0.id })
    }

    var numberInGroup: String {
        selections.count > 0 ? "\(selections.count)" : ""
    }

    var grouping: String {
        selections.count > 0 ? "+" : ""
    }

    func buttonAction(id: String) {
        if selections.contains(id) {
            selections.remove(id)
        } else {
            selections.insert(id)
        }

        let rooms = sonosService.sortedRooms.filter { room in
            selections.contains(room.id)
        }

        guard let group = sonosService.sorted.first(where: { $0.coordinatorID == group.coordinatorID }) else { return }

        Task {
            await sonosService.smartGroup(rooms: rooms, to: group)
        }

    }
}
