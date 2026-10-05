import Foundation
import Observation
import CloudStorage
import OrderedCollections
import Defaults
import SonosKit
import SwiftUI

@Observable
final class SelectedGroupService {
    static var shared = SelectedGroupService()

    /// The group plays go straight to, skipping `PlayDestinationRouter`.
    /// None while no speaker can be reached (Sonos off, or the phone on
    /// cellular): one kept from before would send them to a speaker that
    /// can't answer. Otherwise the live group with the same coordinator,
    /// since a reload replaces every `GroupRoom`, or the one set while it
    /// isn't listed yet (a group just made).
    var group: GroupRoom? {
        get {
            let sonos = SonosService.shared
            guard sonos.isAvailable, let selected else { return nil }
            return sonos.groups.first { $0.coordinatorID == selected.coordinatorID } ?? selected
        }
        set { selected = newValue }
    }

    private var selected: GroupRoom?

    init(group: GroupRoom? = nil) {
        selected = group
    }
}
