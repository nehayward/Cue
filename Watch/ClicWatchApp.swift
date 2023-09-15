import Observation
import SwiftUI
import SonosKit
import WidgetKit

@main
struct ClicWatchApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State var selected: String?

    var sonosService = SonosService()
    var popover = Popover()

    var body: some Scene {
        WindowGroup {
            DeviceListView(selected: $selected)
                .environment(popover)
                .environment(sonosService)
                .onChange(of: selected) {
                    print("Update current")
                    if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                        sonosService.selectedGroup = sonosService.sorted[index]
                    }
                }
//                .overlay(alignment: .top) {
//                    Text("State: \(sonosService.state)")
//                        .fontDesign(.rounded)
//                        .fontWidth(.compressed)
//                        .font(.caption2)
//                        .foregroundStyle(Color.accentColor.gradient)
//                        .padding()
//                        .background(.thickMaterial)
//                        .clipShape(Capsule())
//                }
            
//                .overlay(alignment: .top) {
//                    Text(sonosService.lastKnownIP)
//                        .padding()
//                        .background {
//                            Capsule()
//                                .foregroundStyle(.thinMaterial)
//                        }
//                }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
//                sonosService.monitorWatch()
                sonosService.monitor()

                // MARK: Wait until systemservice fixed
//                Task {
//                    do {
//                        try await sonosService.updateGroupsCheckPlayback()
//                        print("Tock", Date.now)
//                    } catch {
//                        print(error)
//                    }
//                    if selected == nil {
//                        selected = sonosService.groups.first(where: { room in
//                            room.coordinatorRoom.isPlaying
//                        })?.coordinatorID
//                    }
//                }
            case .inactive:
                print("Inactive")
            case .background:
                sonosService.systemNotFound = false
                Task {
                    sonosService.sonosPulse.cancel()
                }
                break
            @unknown default:
                break
            }
        }
    }
}
