//
//  SonosDevicePropertiesEvent.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 1/14/25.
//



struct SonosDevicePropertiesEvent: Sendable {
    var name: String?
    let battery: Battery?
}
