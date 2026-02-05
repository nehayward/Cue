//
//  Allowed.swift
//  SonosKit
//
//  Created by Nick Hayward on 2/3/26.
//
import Foundation

extension CharacterSet {
    /// Safe for Sonos / UPnP / query-style URLs
    /// Escapes characters that break query parsing (&, =, +)
    static let sonosQueryAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
