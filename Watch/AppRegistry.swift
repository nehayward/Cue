import SonosKit
import SwiftUI
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
                }
            }
            .withEnvironments()
        }
    }

//    func withAppRouter(router: Router) -> some View {
//        @Bindable var sonosService = SonosService.shared
//
//        return navigationDestination(for: RouterDestination.self) { destination in
//            switch destination {
//            case let .player(groupID):
//                if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
//                    LargePlayerView(group: $sonosService.sorted[group])
//                } else {
//                    Text("Group No Longer Available")
//                        .onTapGesture {
//                            router.path.removeAll()
//                        }
//                }
//            case let .groupDestination(content):
//                PlayerSelectionView(playableContent: content)
//            case .manageScenes:
//                ManageSceneScreen()
//            }
//        }
//    }

    func withEnvironments() -> some View {
        environment(SonosService.shared)
            .environment(Popover.shared)
            .environment(PlayHistoryService.shared)
    }
}
