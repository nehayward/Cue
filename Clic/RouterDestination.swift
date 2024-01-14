import Foundation
import SonosKit
import SwiftUI

public enum RouterDestination: Hashable {
    case player(groupID: String)
    case groupDestination(content: PlayableContent)
}
