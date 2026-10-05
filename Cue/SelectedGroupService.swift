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
    /// can't answer. It comes back with the speakers.
    var group: GroupRoom? {
        get { SonosService.shared.isAvailable ? selected : nil }
        set { selected = newValue }
    }

    private var selected: GroupRoom?

    init(group: GroupRoom? = nil) {
        selected = group
    }
}
