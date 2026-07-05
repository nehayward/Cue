import Foundation

public enum SpeechLevel: Int, CaseIterable, Codable, Hashable {
    case off = 0
    case low = 1
    case medium = 2
    case high = 3
    case max = 4

    public var title: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .max: return "Max"
        }
    }

    public var isActive: Bool { self != .off }
}
