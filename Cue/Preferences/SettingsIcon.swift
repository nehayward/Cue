import SwiftUI

/// The rounded, gradient-filled glyph at the head of a Preferences row, as
/// the iPhone's Settings draws them. `symbol` names an SF Symbol, or an
/// asset with `isAsset`.
struct SettingsIcon: View {
    let symbol: String
    var isAsset = false
    let colors: [Color]
    var padding: CGFloat = 8

    var body: some View {
        (isAsset ? Image(symbol) : Image(systemName: symbol))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.white)
            .bold()
            .padding(padding)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

/// A row's title over a line of detail, the shape every switch in
/// Preferences has.
struct SettingsRowText: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
