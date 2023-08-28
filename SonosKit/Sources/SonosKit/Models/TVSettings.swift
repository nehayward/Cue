import Foundation
import Observation

@Observable
public class TVSettings {
    public var nightMode: Bool
    public var dialogLevel: Bool

    init(nightMode: Bool, dialogLevel: Bool) {
        self.nightMode = nightMode
        self.dialogLevel = dialogLevel
    }
}
