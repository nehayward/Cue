//
//  RoomState.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 12/20/24.
//



public enum RoomState: Hashable, Sendable {
    case active
    case sleeping
    case poweredOff
    case lowBattery
    case unknown

    init(reason: String) {
        switch reason.lowercased() {
        case "powered off":
            self = .poweredOff
        case "sleeping":
            self = .sleeping
        case "low battery":
            self = .lowBattery
        default:
            self = .unknown
        }
    }

    public var reason: String {
        switch self {
        case .active:
            "Active"
        case .sleeping:
            "Sleeping"
        case .poweredOff:
            "Off"
        case .lowBattery:
            "Low Battery"
        case .unknown:
            "Unknown"
        }
    }

    public var systemSymbol: String {
        switch self {
        case .active:
            ""
        case .sleeping:
            "moon.zzz.fill"
        case .poweredOff:
            "power.circle.fill"
        case .lowBattery:
            "battery.0percent"
        case .unknown:
            ""
        }
    }
}
