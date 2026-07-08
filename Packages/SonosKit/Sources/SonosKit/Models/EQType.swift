import Foundation

public enum EQType: String {
    case dialogLevel = "DialogLevel"
    case nightMode = "NightMode"
    case musicSurroundLevel = "MusicSurroundLevel"
    case surroundEnable = "SurroundEnable"
    case surroundLevel = "SurroundLevel"
    case surroundMode = "SurroundMode"
    case heightChannelLevel = "HeightChannelLevel"
    case subGain = "SubGain"
    case subEnable = "SubEnable"
    case speechEnhanceEnabled = "SpeechEnhanceEnabled"
    case audioDelay = "AudioDelay"

    public var range: ClosedRange<Double> {
        switch self {
        case .dialogLevel:
            0...1
        case .speechEnhanceEnabled:
            0...1
        case .nightMode:
            0...1
        case .musicSurroundLevel:
            -15...15
        case .subGain:
            -15...15
        case .surroundEnable:
            0...1
        case .subEnable:
            -10...10
        case .surroundLevel:
            -15...15
        case .surroundMode:
            0...1
        case .heightChannelLevel:
            -10...10
        case .audioDelay:
            0...5
        }
    }
}
