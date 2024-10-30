import Observation
import SonosKit

@MainActor
@Observable
final class MiniPlayerManger {
    var offset: Double = 0

    static var shared = MiniPlayerManger()
}
