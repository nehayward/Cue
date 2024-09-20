import SwiftUI

extension View {
    @ViewBuilder
    func paywall(_ isEnabled: Bool) -> some View {
        if !isEnabled {
            disabled(!isEnabled)
                .selectionDisabled(!isEnabled)
                .redacted(reason: .placeholder)
                .overlay {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        Router.main.sheet(to: .paywall)
                    } label: {
                        Text("Upgrade to unlock")
                            .bold()
                            .fontDesign(.rounded)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }
        } else {
            self
        }
    }
}
