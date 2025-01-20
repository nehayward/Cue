import Foundation

struct SonosRenderingControlEvent {
    // Volume controls
    let masterVolume: Int
    
    // Mute controls
    let masterMute: Bool
    
    // Audio settings
    let bass: Int
    let treble: Int
    let loudness: Bool
    let outputFixed: Bool
    
    // Speaker configuration
    let speakerSize: Int?
    let subGain: Int?
    let subCrossover: Int?
    let subPolarity: Int?
    let subEnabled: Bool?
    
    // Dialog and surround settings
    let dialogLevel: Int?
    let speechEnhanceEnabled: Bool?
    let surroundLevel: Int?
    let musicSurroundLevel: Int?
    
    // Delay settings
    let audioDelay: Int?
    
    // Mode settings
    let nightMode: Bool?
    let surroundEnabled: Bool?
    let surroundMode: Int?
    
    // Additional settings
    let heightChannelLevel: Int?
    let sonarEnabled: Bool?
    let sonarCalibrationAvailable: Bool?
    let presetNameList: String?
    
    init(
        masterVolume: Int,
        masterMute: Bool,
        bass: Int,
        treble: Int,
        loudness: Bool,
        outputFixed: Bool,
        speakerSize: Int? = nil,
        subGain: Int? = nil,
        subCrossover: Int? = nil,
        subPolarity: Int? = nil,
        subEnabled: Bool? = nil,
        dialogLevel: Int? = nil,
        speechEnhanceEnabled: Bool? = nil,
        surroundLevel: Int? = nil,
        musicSurroundLevel: Int? = nil,
        audioDelay: Int? = nil,
        nightMode: Bool? = nil,
        surroundEnabled: Bool? = nil,
        surroundMode: Int? = nil,
        heightChannelLevel: Int? = nil,
        sonarEnabled: Bool? = nil,
        sonarCalibrationAvailable: Bool? = nil,
        presetNameList: String? = nil
    ) {
        self.masterVolume = masterVolume
        self.masterMute = masterMute
        self.bass = bass
        self.treble = treble
        self.loudness = loudness
        self.outputFixed = outputFixed
        self.speakerSize = speakerSize
        self.subGain = subGain
        self.subCrossover = subCrossover
        self.subPolarity = subPolarity
        self.subEnabled = subEnabled
        self.dialogLevel = dialogLevel
        self.speechEnhanceEnabled = speechEnhanceEnabled
        self.surroundLevel = surroundLevel
        self.musicSurroundLevel = musicSurroundLevel
        self.audioDelay = audioDelay
        self.nightMode = nightMode
        self.surroundEnabled = surroundEnabled
        self.surroundMode = surroundMode
        self.heightChannelLevel = heightChannelLevel
        self.sonarEnabled = sonarEnabled
        self.sonarCalibrationAvailable = sonarCalibrationAvailable
        self.presetNameList = presetNameList
    }
}
