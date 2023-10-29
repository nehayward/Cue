import SonosKit
import Observation

@Observable
final class GroupScreenViewModel {
    var group: GroupRoom
    var selections: Set<String>
    private let initialSelection: Set<String>

    init(group: GroupRoom) {
        self.group = group
        let ids = Set(group.rooms.map { $0.id })
        self.selections = ids
        self.initialSelection = ids
    }

    var groupingLabel: String {
        if selections == initialSelection {
            return "Cancel"
        }
        if selections.count >= initialSelection.count {
            return "Grouping"
        } else {
            return "Separating"
        }
    }

    var numberInGroup: String {
        if selections == initialSelection, selections.count > 0 {
            return "\(initialSelection.count)"
        }

        return selections.count > 0 ? "\(selections.count)" : ""
    }

    func buttonAction(id: String) {
        if selections.contains(id) {
            selections.remove(id)
        } else {
            selections.insert(id)
        }
    }
}
