import SwiftUI
import SonosKit

struct LogView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    let fileName: String
    @State private var log = ""


    var body: some View {
        ScrollView {
            Text(log)
                .textSelection(.enabled)
        }
        .onAppear {
            sonosService.monitor()

            guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appending(path: "Logs") else {
                print("Documents directory not found")
                return
            }

            let fileURL = documentDirectory.appendingPathComponent(fileName)

            do {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                log = contents
            } catch {
                print("Error reading file: \(error)")
                log = "Error"
            }
        }
    }
}

#Preview {
    LogScreen()
        .environment(SonosService())
}

