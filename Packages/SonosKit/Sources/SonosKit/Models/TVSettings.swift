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

    /// Combined speech enhancement level for Arc Ultra: 0=Off, 1=Low, 2=Medium, 3=High, 4=Max
    public var speechLevel: Int {
        guard speechEnhanceEnabled == true else { return 0 }
        return max(1, min(4, dialogLevelValue))
    }

    public var speechLevelDescription: String {
        switch speechLevel {
        case 1: return "Low"
        case 2: return "Medium"
        case 3: return "High"
        case 4: return "Max"
        default: return "Off"
        }
    }

    public init(nightMode: Bool, dialogLevel: Bool, speechEnhanceEnabled: Bool? = nil, dialogLevelValue: Int = 1, audioInputFormat: AudioInputFormat) {
        self.nightMode = nightMode
        self.dialogLevel = dialogLevel
        self.speechEnhanceEnabled = speechEnhanceEnabled
        self.dialogLevelValue = dialogLevelValue
        self.audioInputFormat = audioInputFormat
    }
}
