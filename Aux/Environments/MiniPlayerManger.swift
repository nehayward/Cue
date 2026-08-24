import Observation
import SonosKit

@MainActor
@Observable
final class MiniPlayerManger {
    var offset: Double = 0
    var hidden: Bool = false

    static var shared = MiniPlayerManger()
}
