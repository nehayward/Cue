import Foundation

/// Debug builds keep the last of each kind of speaker response in
/// Documents/Logs, to read when a speaker misbehaves.
final class SonosLogInformation: @unchecked Sendable {
    static let shared = SonosLogInformation()

    /// Writes one at a time, in order, off the main thread: speaker polls
    /// log a response every few seconds, and each was a file write on the
    /// main thread.
    private let queue = DispatchQueue(label: "dance.cue.sonosLog", qos: .utility)

    /// `message` is only built in debug builds, and there off the main
    /// thread: callers hand over whole speaker responses (unescaped), which
    /// release builds used to build on every poll and then drop.
    func log(name: String, _ message: @autoclosure @escaping () -> String) {
#if DEBUG
        queue.async {
            let logMessage = message()

            guard let logDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appending(path: "Logs") else {
                return
            }

            // Check if the directory exists; if not, create it.
            if !FileManager.default.fileExists(atPath: logDirectory.path) {
                do {
                    try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
                    print("Logs directory created successfully at \(logDirectory.path)")
                } catch {
                    print("Failed to create directory: \(error)")
                }
            }

            let logFileURL = logDirectory.appendingPathComponent(name)

            do {
                try logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to log message: \(error)")
            }
        }
#endif
    }
}
