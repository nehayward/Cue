import SonosKit
import Observation

@Observable
final class GroupScreenViewModel {
    var group: GroupRoom
    var selections: Set<String>
    private let initialSelection: Set<String>

    init(group: GroupRoom) {
        self.group = group

        var ids = Set(group.rooms.map { $0.id })
        ids.remove(group.coordinatorRoom.id)
        self.selections = ids
        self.initialSelection = ids
    }

    var groupingLabel: String {
        if selections == initialSelection {
            return "Cancel"
        }
        if selections.count > initialSelection.count {
            return "Grouping \(selections.count)"
        }

        if selections.count < initialSelection.count {
            return "Ungroup"
        }

        return "Group"
    }

    func buttonAction(id: String) {
        if selections.contains(id) {
            selections.remove(id)
        } else {
            selections.insert(id)
        }
    }
}
