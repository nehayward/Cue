import Foundation

/// Bytes per second over the last few seconds, read off the running total
/// of bytes received across every transfer.
public struct TransferRateMeter: Sendable {
    struct Sample: Sendable {
        let time: Date
        let total: Int64
    }

    /// How far back the rate looks.
    public let window: TimeInterval
    /// The shortest span a rate is given for; less is noise.
    public let minimumSpan: TimeInterval
    private var samples: [Sample] = []

    public init(window: TimeInterval = 5, minimumSpan: TimeInterval = 1) {
        self.window = window
        self.minimumSpan = minimumSpan
    }

    /// Records the running total at a moment. A total that went backwards
    /// means a new count started; the meter starts over with it.
    public mutating func record(total: Int64, at time: Date) {
        if let last = samples.last, total < last.total || time < last.time {
            samples.removeAll()
        }
        samples.append(Sample(time: time, total: total))
        // Keep one sample from before the window as its baseline, so the
        // rate always spans the whole window once there's that much.
        let start = time.addingTimeInterval(-window)
        while samples.count > 2, samples[1].time <= start {
            samples.removeFirst()
        }
    }

    /// The rate over the window, or nil until it spans `minimumSpan`.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        guard span >= minimumSpan else { return nil }
        return Double(last.total - first.total) / span
    }

    public mutating func reset() {
        samples.removeAll()
    }
}

/// Which way the watch's downloads are going, as far as their speed tells.
public enum DownloadRoute: String, Sendable, Equatable {
    /// Not enough transfer yet to tell.
    case measuring
    /// Fast enough to be the watch's own Wi‑Fi.
    case wifi
    /// Slow: through the iPhone, over Bluetooth.
    case throughPhone
}

/// Tells Wi‑Fi from the iPhone relay by speed.
///
/// watchOS doesn't say which way a `URLSession` transfer goes: while the
/// iPhone is connected over Bluetooth the system sends the watch's traffic
/// through it, and `NWPathMonitor` stays unsatisfied for an app that isn't
/// streaming audio (TN3135). So the speed is the evidence. Bluetooth through
/// the iPhone manages tens to a couple of hundred KB/s; the watch's own
/// Wi‑Fi, MB/s. A transfer has to run `settleTime` before it's called slow
/// (a connection takes a moment to get going), but one that's plainly fast
/// is called Wi‑Fi at once. In between the two thresholds the verdict
/// holds, so it doesn't flicker on a server that runs near the line.
public struct RouteEstimator: Sendable {
    /// At or above this, Wi‑Fi.
    public static let fastRate: Double = 400_000
    /// Below this, through the iPhone.
    public static let slowRate: Double = 250_000
    public static let settleTime: TimeInterval = 5

    public private(set) var route: DownloadRoute = .measuring
    private var startedAt: Date?

    public init() {}

    /// Takes the latest rate (nil while the meter has too little to go on)
    /// and returns the verdict.
    @discardableResult
    public mutating func update(bytesPerSecond rate: Double?, at time: Date) -> DownloadRoute {
        let start = startedAt ?? time
        startedAt = start
        guard let rate else { return route }
        let settled = time.timeIntervalSince(start) >= Self.settleTime
        switch route {
        case .measuring:
            if rate >= Self.fastRate {
                route = .wifi
            } else if settled {
                route = rate < Self.slowRate ? .throughPhone : .wifi
            }
        case .wifi:
            if settled, rate < Self.slowRate { route = .throughPhone }
        case .throughPhone:
            if rate >= Self.fastRate { route = .wifi }
        }
        return route
    }

    /// Back to measuring, for when transfers stop and start again — the
    /// network may have changed in between.
    public mutating func reset() {
        route = .measuring
        startedAt = nil
    }
}
