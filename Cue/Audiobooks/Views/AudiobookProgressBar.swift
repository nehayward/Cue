import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A slim listening-progress bar for a book: its rows, its cover and its
/// page. From Clic's Audible screens.
struct AudiobookProgressBar: View {
    let fraction: Double
    var height: Double = 3
    var tint: Color = .accentColor
    /// Rounded ends, or square ones (on a cover's hard edge).
    var isRounded: Bool = true

    /// Read with `onGeometryChange` rather than a `GeometryReader`, which
    /// re-runs its content on every layout pass.
    @State private var width: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isRounded ? height / 2 : 0)
        shape
            .fill(.secondary.opacity(0.35))
            .overlay(alignment: .leading) {
                shape
                    .fill(tint)
                    .frame(width: width * min(max(fraction, 0), 1))
            }
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .accessibilityElement()
            .accessibilityLabel("Listening progress")
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
