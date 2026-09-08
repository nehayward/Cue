import SwiftUI

/// The gear in a browse screen's top-right corner that opens Settings —
/// the same sheet the Home tab and the provider menu reach, one tap
/// closer.
struct SettingsToolbarButton: View {
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            router.presentedSheet = .settings()
        } label: {
            Label("Settings", systemImage: "gear")
                .labelStyle(.iconOnly)
        }
    }
}
