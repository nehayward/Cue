import Foundation
import Observation
import CloudStorage
import OrderedCollections
import Defaults
import SonosKit
import SwiftUI

@Observable
final class SelectedGroupService {
    var group: GroupRoom?

    init(group: GroupRoom? = nil) {
        self.group = group
    }
}
