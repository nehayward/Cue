import RevenueCatUI
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
                }
            }
        }
    }
}
