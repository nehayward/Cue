import SwiftUI
import OSLog
import Analytics

struct LoggerView: View {
    @State private var text = "Send Logs..."

    var body: some View {
        Button {
            text = "Sent"
        } label: {
            Text(text)
                .padding()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .task(id: text) {
            let text = await fetchBeaverLogs()
            await uploadLogs(text: text)
        }
        .listRowSeparator(.hidden)
    }
}

extension LoggerView {
    static private let template = NSPredicate(format:
                                                "(subsystem BEGINSWITH $PREFIX) || ((subsystem IN $SYSTEM) && ((messageType == error) || (messageType == fault)))")

    @MainActor
    private func fetchLogs() async -> String {
        let calendar = Calendar.current
        guard let dayAgo = calendar.date(byAdding: .day,
                                         value: -1, to: Date.now) else {
            return "Invalid calendar"
        }

        do {
            let predicate = LoggerView.template.withSubstitutionVariables(
                [
                    "PREFIX": "com.cue",
                    "SYSTEM": []
                ])

            let logs = try await Logger.fetch(since: dayAgo,
                                              predicateFormat: predicate.predicateFormat)
            return logs.joined()
        } catch {
            return error.localizedDescription
        }
    }

    @MainActor
    private func fetchBeaverLogs() async -> String {
        let fm = FileManager.default
        let beaverLogs = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!.appending(path: "swiftybeaver.log")
        let fileContents = try? String(contentsOf: beaverLogs, encoding: .utf8)
        return "[\(fileContents ?? "No Logs")]"
    }

    private func uploadLogs(text: String) async {
        if text.isEmpty { return }
        // Define the URL and request
        guard let id =  UIDevice.current.identifierForVendor?.uuidString else { return }
        guard let url = URL(string: "https://tight-night-3b05.nehayward.workers.dev/\(Date.now.ISO8601Format(.iso8601Date(timeZone: .current, dateSeparator: .omitted)))_\(id).txt") else {
            fatalError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("Bearer cue6043", forHTTPHeaderField: "Authorization")
        request.httpBody = text.data(using: .utf8)

        // Perform the async URLSession call
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("Status Code: \(httpResponse.statusCode)")
            }

            // Handle the response data
            if let responseData = String(data: data, encoding: .utf8) {
                print("Response Data: \(responseData)")
            }
        } catch {
            print("Request failed with error: \(error)")
        }
    }
}


extension OSLogEntryLog.Level {
    fileprivate var description: String {
        switch self {
        case .undefined: "undefined"
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        @unknown default: "default"
        }
    }
}


extension Logger {
    static public func fetch(since date: Date,
                             predicateFormat: String) async throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: date)
        let predicate = NSPredicate(format: predicateFormat)
        let entries = try store.getEntries(at: position,
                                           matching: predicate)

        var logs: [String] = []
        for entry in entries {
            try Task.checkCancellation()
            if let log = entry as? OSLogEntryLog {
                logs.append("""
          \(entry.date):\(log.subsystem):\
          \(log.category):\(log.level.description): \
          \(entry.composedMessage)\n
          """)
            } else {
                logs.append("\(entry.date): \(entry.composedMessage)\n")
            }
        }

        if logs.isEmpty { logs = ["Nothing found"] }
        return logs
    }
}


