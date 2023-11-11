import SonosKit
import Observation

@Observable
final class GroupScreenViewModel {
    var group: GroupRoom
    var selections: Set<String>
    private let initialSelection: Set<String>

    init(group: GroupRoom) {
        self.group = group
        let ids = Set(group.rooms.filter { $0.id != group.coordinatorID }.map { $0.id })
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
        if selections.count >= initialSelection.count {
            return selections.count > 0 ? "\(selections.count)" : ""
        } else {
            return "\(initialSelection.symmetricDifference(selections).count)"
        }
    }

    var grouping: String {
        if selections.count >= initialSelection.count {
            return selections.count > 0 ? "+" : ""
        } else {
            return "-"
        }
    }

    func buttonAction(id: String) {
        if selections.contains(id) {
            selections.remove(id)
        } else {
            selections.insert(id)
        }
    }
}
