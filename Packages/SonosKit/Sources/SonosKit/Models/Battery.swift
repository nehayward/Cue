import Foundation

public struct Battery {
    public let percentage: Double
    public let chargingState: ChargingState
    public let batteryTemperature: Double

    init?(info: String) {
        if info.isEmpty { return nil }
        let components = info.split(separator: ",").map { $0.split(separator: ":") }
        var infoDict: [String: String] = [:]
        for component in components {
            if component.count == 2 {
                infoDict[String(component[0])] = String(component[1])
            }
        }

        if let rawBattPct = infoDict["RawBattPct"], let percentage = Double(rawBattPct) {
            self.percentage = percentage
        } else {
            return nil
        }

        switch infoDict["BattChg"] {
        case "CHARGING":
            self.chargingState = .charging
        default:
            self.chargingState = .notCharging
        }

        if let battTmp = infoDict["BattTmp"], let batteryTemperature = Double(battTmp) {
            self.batteryTemperature = batteryTemperature
        } else {
            return nil
        }
    }
}

public enum ChargingState {
    case charging
    case notCharging
}
