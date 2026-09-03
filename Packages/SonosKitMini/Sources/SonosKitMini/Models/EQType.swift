import Foundation

/// The EQ types Cue Mini and the Watch read and write. Mirrors SonosKit's `EQType`
/// — the two packages don't share models, but the raw values are the wire format and
/// have to match.
public enum EQType: String {
    case dialogLevel = "DialogLevel"
    case nightMode = "NightMode"
    case speechEnhanceEnabled = "SpeechEnhanceEnabled"
}
