import Foundation

public struct Alarm: Hashable, Identifiable, Equatable {
    public var id: String
    public var roomID: String
    public var enabled: Bool
    public var startTime: Date
    public var duration: Duration
    public var schedule: Set<Schedule>
    public var programURI: String
    public var programMetaData: String?
    public var volume: Double
    public var includeLinkedZones: Bool
    public var playMode: PlayMode
    public var shuffle: Bool
    public var scheduleRaw: String

    public init(id: String, roomID: String, enabled: Bool, startTime: Date, duration: Duration, schedule: Set<Schedule>, programURI: String, programMetaData: String? = nil, volume: Double, includeLinkedZones: Bool, playMode: PlayMode, scheduleRaw: String, shuffle: Bool) {
        self.id = id
        self.roomID = roomID
        self.enabled = enabled
        self.startTime = startTime
        self.duration = duration
        self.schedule = schedule
        self.programURI = programURI
        self.programMetaData = programMetaData
        self.volume = volume
        self.includeLinkedZones = includeLinkedZones
        self.playMode = playMode
        self.scheduleRaw = scheduleRaw
        self.shuffle = shuffle
    }

    public static var newAlarm: Self {
        Self(
            id: "",
            roomID: "",
            enabled: true,
            startTime: .now,
            duration: .zero,
            schedule: [.once],
            programURI: "x-rincon-buzzer:0",
            volume: 10,
            includeLinkedZones: false,
            playMode: [.normal],
            scheduleRaw: "ONCE",
            shuffle: true
        )
    }

    public var durationAlarm: String {
        let hours =  Int(duration.components.seconds % 86400) / 3600
        let minutes =  Int(duration.components.seconds % 3600) / 60
        return "\(hours):\(minutes):00"
    }
}

public enum Schedule: String, CaseIterable, Hashable, Identifiable {
    public var id: String { rawValue }

    case once
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public var title: String {
        rawValue.capitalized
    }

    public var shortTitle: String {
        if self == .once {
            return "Once"
        }
        return String(rawValue.capitalized.prefix(2))
    }

    public var order: Int {
        switch self {
        case .once:
            8
        case .monday:
            1
        case .tuesday:
            2
        case .wednesday:
            3
        case .thursday:
            4
        case .friday:
            5
        case .saturday:
            6
        case .sunday:
            0
        }
    }
}

public typealias Frequency = Set<Schedule>

extension Frequency {
    public init(mode: String) {
        switch mode.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "once":
            self = [.once]
        case "weekdays":
            self = [.monday, .tuesday, .wednesday, .thursday, .friday]
        case "weekends":
            self = [.saturday, .sunday]
        case "daily":
            self = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        default:
            var schedule: Set<Schedule> = []
            if mode.contains("0") {
                schedule.insert(.sunday)
            }
            if mode.contains("1") {
                schedule.insert(.monday)
            }
            if mode.contains("2") {
                schedule.insert(.tuesday)
            }
            if mode.contains("3") {
                schedule.insert(.wednesday)
            }
            if mode.contains("4") {
                schedule.insert(.thursday)
            }
            if mode.contains("5") {
                schedule.insert(.friday)
            }
            if mode.contains("6") {
                schedule.insert(.saturday)
            }

            self = schedule
        }
    }

    public var alarmSchedule: String {
        switch self {
        case [.once]:
            return "ONCE"
        case [.monday, .tuesday, .wednesday, .thursday, .friday]:
            return "WEEKDAYS"
        case [.saturday, .sunday]:
            return "WEEKENDS"
        case [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]:
            return "DAILY"
        default:
            let schedule = "ON_" + self.map(\.order).map(String.init).joined()
            return schedule
        }
    }
}
