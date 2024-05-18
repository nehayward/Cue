import SwiftUI
import SonosKit

struct LogScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var groupXML = ""
    @State var tracks = ""

    var body: some View {
        NavigationStack {
            Form {
                NavigationLink("Group") {
                    ScrollView {
                        Text(groupXML)
                            .textSelection(.enabled)
                    }
                }

                NavigationLink("Tracks") {
                    Form {
                        ForEach(sonosService.groups) { group in
                            NavigationLink(group.coordinatorRoom.name) {
                                LogView(fileName: group.coordinatorRoom.ip + "_track.txt")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            sonosService.monitor()

            guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appending(path: "Logs") else {
                print("Documents directory not found")
                return
            }

            let fileURL = documentDirectory.appendingPathComponent("Groups.txt")

            do {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                groupXML = contents
            } catch {
                print("Error reading file: \(error)")
                groupXML = "Error"
            }
        }
    }
}

#Preview {
    LogScreen()
        .environment(SonosService())
}

