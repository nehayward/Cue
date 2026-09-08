import SwiftUI

/// The phone's Browse tab while `OfflineMode` is active. Browse is the
/// phone's home, and its provider screens have nothing to show with no
/// network, so this stands in with what's on this device — the same
/// sections Home shows on iPad and Mac — until the network is back or
/// the switch is off.
struct OfflineBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var router = Router.browse

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                OfflineSections()
            }
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .contentMargins(.horizontal, 16)
            .miniPlayerOnScrollHandler()
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Offline")
            .navigationBarTitleDisplayMode(.inline)
            .withAppRouter()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.presentedSheet = .settings()
                    } label: {
                        Label("Settings", systemImage: "gear")
                            .labelStyle(.iconOnly)
                    }
                }
            }
#if !targetEnvironment(macCatalyst)
            .addDismiss {
                dismiss()
                Router.main.inspectorSheet = nil
            }
#endif
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }
}

#Preview {
    OfflineBrowseScreen()
        .withEnvironments()
}
