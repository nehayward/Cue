import Observation

@Observable
final class Popover {
    static var shared = Popover()
    
    var isShowing: Bool = false
    var text: String = ""
}
