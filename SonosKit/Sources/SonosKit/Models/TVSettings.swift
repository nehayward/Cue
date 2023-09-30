import Foundation
import Observation

@Observable
public class TVSettings {
    public var nightMode: Bool
    public var dialogLevel: Bool
    public var audioFormat: String

    init(nightMode: Bool, dialogLevel: Bool, audioFormat: String) {
        self.nightMode = nightMode
        self.dialogLevel = dialogLevel
        self.audioFormat = audioFormat
    }
}
