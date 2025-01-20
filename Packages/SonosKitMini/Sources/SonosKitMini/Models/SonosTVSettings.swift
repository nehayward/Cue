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
    public var audioInputFormat: AudioInputFormat?

    public init(nightMode: Bool, dialogLevel: Bool, audioInputFormat: AudioInputFormat?) {
        self.nightMode = nightMode
        self.dialogLevel = dialogLevel
        self.audioInputFormat = audioInputFormat
    }
}
