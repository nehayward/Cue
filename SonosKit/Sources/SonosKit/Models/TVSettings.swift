import Foundation
import Observation

@Observable
public class TVSettings {
    public var nightMode: Bool
    public var dialogLevel: Bool
    public var audioInputFormat: AudioInputFormat

    init(nightMode: Bool, dialogLevel: Bool, audioInputFormat: AudioInputFormat) {
        self.nightMode = nightMode
        self.dialogLevel = dialogLevel
        self.audioInputFormat = audioInputFormat
    }
}
