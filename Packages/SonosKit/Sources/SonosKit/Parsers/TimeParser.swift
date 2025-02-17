import Foundation

final class TimeParser {
    static let shared = TimeParser()
    
    private init() {}
    
    func parseDuration(_ durationString: String) -> Duration {
        guard !durationString.isEmpty else { return .zero }
        
        // Use substring operations instead of components for better performance
        let firstColon = durationString.firstIndex(of: ":")
        let lastColon = durationString.lastIndex(of: ":")
        
        guard let firstColon = firstColon,
              let lastColon = lastColon,
              firstColon != lastColon else { return .zero }
        
        let hours = String(durationString[..<firstColon])
        let minutes = String(durationString[durationString.index(after: firstColon)..<lastColon])
        let seconds = String(durationString[durationString.index(after: lastColon)...])
        
        guard let hoursInt = Int(hours),
              let minutesInt = Int(minutes),
              let secondsInt = Int(seconds) else { return .zero }
        
        let totalSeconds = (hoursInt * 3600) + (minutesInt * 60) + secondsInt
        return .seconds(totalSeconds)
    }
    
    func parseTime(_ timeString: String) -> Date {
        var day = Calendar.current.startOfDay(for: .now)
        
        // Use the same substring approach for consistency and performance
        let firstColon = timeString.firstIndex(of: ":")
        let lastColon = timeString.lastIndex(of: ":")
        
        guard let firstColon = firstColon,
              let lastColon = lastColon,
              firstColon != lastColon else { return day }
        
        let hours = String(timeString[..<firstColon])
        let minutes = String(timeString[timeString.index(after: firstColon)..<lastColon])
        let seconds = String(timeString[timeString.index(after: lastColon)...])
        
        guard let hoursInt = Int(hours),
              let minutesInt = Int(minutes),
              let secondsInt = Int(seconds) else { return day }
        
        day.addTimeInterval(Double((hoursInt * 3600) + (minutesInt * 60) + secondsInt))
        return day
    }
}

// End of file. No additional code.
