import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

enum AudiobookFormat {
    /// "5h 3m", "42m": how long, to the minute, in the narrow form.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded()), seconds > 0 ? 1 : 0)
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// What the listener has left, or that they've finished.
    static func remaining(_ progress: AudiobookProgress) -> String? {
        if progress.isFinished { return "Finished" }
        guard progress.isStarted, progress.duration > 0 else { return nil }
        return "\(duration(progress.remaining)) left"
    }

    /// "1:02:15" for a place in a book.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
