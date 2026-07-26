import Foundation
import Observation

public struct TVSettings: Codable, Hashable, Equatable {
    public var nightMode: Bool
    public var dialogLevel: Bool
    /// Arc Ultra only: nil means unsupported
    public var speechEnhanceEnabled: Bool?
    /// Arc Ultra only: dialog intensity level (1=Low, 2=Medium, 3=High, 4=Max)
    public var dialogLevelValue: Int
    public var audioInputFormat: AudioInputFormat

    /// True when speech enhancement is active on either device type.
    public var speechIsActive: Bool {
        speechEnhanceEnabled != nil ? speechLevel.isActive : dialogLevel
    }

    /// Combined speech enhancement level for Arc Ultra.
    public var speechLevel: SpeechLevel {
        guard speechEnhanceEnabled == true else { return .off }
        return SpeechLevel(rawValue: max(1, min(4, dialogLevelValue))) ?? .low
    }

    public init(nightMode: Bool, dialogLevel: Bool, speechEnhanceEnabled: Bool? = nil, dialogLevelValue: Int = 1, audioInputFormat: AudioInputFormat) {
        self.nightMode = nightMode
        self.dialogLevel = dialogLevel
        self.speechEnhanceEnabled = speechEnhanceEnabled
        self.dialogLevelValue = dialogLevelValue
        self.audioInputFormat = audioInputFormat
    }
}
