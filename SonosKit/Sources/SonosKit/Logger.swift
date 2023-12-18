import Foundation

class SonosLogInformation {
    static let shared = SonosLogInformation()
    private var logFileURL: URL?


    func log(name: String, _ message: String) {
#if DEBUG
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .long)
        let logMessage = "\(message)"

        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let logFileURL = documentDirectory.appendingPathComponent(name)

        do {
            try logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to log message: \(error)")
        }
#endif
    }
    
}
