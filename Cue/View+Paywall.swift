import SwiftUI

extension View {
    @ViewBuilder
    func paywall(_ isEnabled: Bool) -> some View {
        if !isEnabled {
            disabled(!isEnabled)
                .selectionDisabled(!isEnabled)
                .redacted(reason: .placeholder)
                .frame(maxWidth: .infinity)
                .overlay {
                    // Whole-row tap target — no visible pill, just a clear
                    // hit area. Previous design stacked a centered "Tap to
                    // Unlock" pill on every locked row, which competed with
                    // the PaywallButtonView card sitting just below. The
                    // redaction is enough of a "you can't access this" cue;
                    // the corner lock glyph clarifies that it's locked rather
                    // than loading.
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        Router.main.fullScreenCover(to: .paywall)
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
        } else {
            self
        }
    }
}
