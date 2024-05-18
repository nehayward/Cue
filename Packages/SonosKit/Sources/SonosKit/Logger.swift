import Foundation

class SonosLogInformation {
    static let shared = SonosLogInformation()
    private var logFileURL: URL?


    func log(name: String, _ message: String) {
//#if DEBUG
        let logMessage = "\(message)"

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
//#endif
    }
    
}
