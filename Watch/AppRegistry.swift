import SonosKit
import SwiftUI
import SonosKitMini
import VibesDS

@MainActor
extension View {
    func withSheetDestinations(sheetDestinations: Binding<SheetDestination?>) -> some View {
        sheet(item: sheetDestinations) { destination in
            Group {
                switch destination {
                case .preferences:
                    PreferenceScreen()
                case .scenes:
                    SceneView()
//                    SceneView()
                }
            }
            .withEnvironments()
        }
    }
    
    func withAppRouter() -> some View {
        navigationDestination(for: Path.self) { destination in
            switch destination {
            case let .player(id):
                PlayerScreen(id: id)
            default:     
                Text("Group No Longer Available")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    func withEnvironments() -> some View {
        environment(SonosMiniService.shared)
            .environment(Popover.shared)
            .environment(PlayHistoryService.shared)
    }
}
