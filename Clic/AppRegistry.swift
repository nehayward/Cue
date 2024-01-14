import RevenueCatUI
import SubscriptionKit
import SonosKit
import SwiftUI

@MainActor
extension View {
    func withSheetDestinations(sheetDestinations: Binding<SheetDestination?>) -> some View {
        sheet(item: sheetDestinations) { destination in
            Group {
                switch destination {
                case let .groupScreen(groupScreenViewModel, group):
                    GroupScreen(id: group.coordinatorID, sheetDestination: sheetDestinations, viewModel: groupScreenViewModel)
                case .paywall:
                    PaywallView()
                case .settings:
                    PreferenceScreen()
                case let .search(group):
                    ImprovedSearch(group: group)
                case let .queue(group):
                    QueueScreen(group: group)
                        .presentationDetents([.medium, .large])
                case let .playContent(content):
                    PlayerSelectionView(playableContent: content)
                case let .playMedia(content):
                    NavigationStack {
                        PlayerSelectionView(mediaContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .navigationTitle("Choose Group")
                    }
                }
            }
            .withEnvironments()
        }
    }

    func withAppRouter(router: RouterPath) -> some View {
        @Bindable var sonosService = SonosService.shared

        return navigationDestination(for: RouterDestination.self) { destination in
            switch destination {
            case let .player(groupID):
                if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                    LargePlayerView(group: $sonosService.sorted[group])
                } else {
                    Text("Group No Longer Available")
                        .onTapGesture {
                            router.path.removeAll()
                        }
                }
            case let .groupDestination(content):
                PlayerSelectionView(playableContent: content)
            }
        }
    }

    func withEnvironments() -> some View {
        environment(SonosService.shared)
            .environment(SubscriptionService.shared)
            .environment(AlertService.shared)
    }
}
