import Foundation
import MusicSearchKit

/// How a book's times read on the watch.
enum WatchBookFormat {
    /// A length: "5 hr, 3 min".
    static func length(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "Under a minute" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// What's left of a book, or that it's finished; its length when it
    /// hasn't been started.
    static func status(_ progress: AudiobookProgress?, duration: TimeInterval) -> String {
        if let progress, progress.isFinished {
            return "Finished"
        }
        if let progress, progress.isStarted {
            let left = max((progress.duration > 0 ? progress.duration : duration) - progress.position, 0)
            return left < 60 ? "Under a minute left" : "\(length(left)) left"
        }
        return duration > 0 ? length(duration) : ""
    }

    /// A speed: "1.25×".
    static func rate(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0 ... 2))))×"
    }
}
