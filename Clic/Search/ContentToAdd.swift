import Observation
import SonosKit

@Observable
final class ContentToAdd {
    var add: Bool
    var content: PlayableContent?

    init(add: Bool) {
        self.add = add
    }
}
