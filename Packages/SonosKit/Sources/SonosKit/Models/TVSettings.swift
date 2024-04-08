import Foundation
import Observation

public struct TVSettings: Codable, Hashable, Equatable {
    public var nightMode: Bool
    public var dialogLevel: Bool
    public var audioInputFormat: AudioInputFormat

    public init(nightMode: Bool, dialogLevel: Bool, audioInputFormat: AudioInputFormat) {
        self.nightMode = nightMode
        self.dialogLevel = dialogLevel
        self.audioInputFormat = audioInputFormat
    }
}
