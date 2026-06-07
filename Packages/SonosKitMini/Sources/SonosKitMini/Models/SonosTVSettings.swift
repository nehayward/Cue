//
//  TVSettings.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 12/20/24.
//
import Foundation

public struct SonosTVSettings: Codable, Hashable, Equatable, Sendable {
    public var nightMode: Bool
    public var dialogLevel: Bool
    /// Arc Ultra only: nil means unsupported
    public var speechEnhanceEnabled: Bool?
    /// Arc Ultra only: dialog intensity level (1=Low, 2=Medium, 3=High, 4=Max)
    public var dialogLevelValue: Int
    public var audioInputFormat: AudioInputFormat?

    public init(nightMode: Bool, dialogLevel: Bool, speechEnhanceEnabled: Bool? = nil, dialogLevelValue: Int = 1, audioInputFormat: AudioInputFormat?) {
        self.nightMode = nightMode
        self.dialogLevel = dialogLevel
        self.speechEnhanceEnabled = speechEnhanceEnabled
        self.dialogLevelValue = dialogLevelValue
        self.audioInputFormat = audioInputFormat
    }
}
