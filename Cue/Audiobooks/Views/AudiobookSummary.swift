import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's description: four lines, the last fading out, opening out to
/// the whole of it at a tap anywhere on it, and closing again the same way.
/// The text is laid out whole either way and only the frame showing it
/// grows, so it opens as one smooth reveal rather than jumping from one
/// layout of the text to another (a changing `lineLimit` re-wraps it
/// mid-animation); as a geometry group it reaches the page as a single
/// change of size, which the rows below follow in step. Until it's been
/// measured (its first frame) it's its first four lines, the height it
/// then keeps: drawn at no height until then, it opened a frame late and
/// pushed the page under it down.
struct AudiobookSummary: View {
    let text: String

    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    private static let collapsedLines = 4

    private var isMeasured: Bool { fullHeight > 0 && collapsedHeight > 0 }
    private var truncates: Bool { fullHeight > collapsedHeight + 1 }
    private var isCollapsed: Bool { truncates && !isExpanded }

    var body: some View {
        Text(text)
            .lineLimit(isMeasured ? nil : Self.collapsedLines)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: isMeasured ? (isCollapsed ? collapsedHeight : fullHeight) : nil, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            // The last line fading out says there's more.
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: isCollapsed ? 24 : 0)
                }
            }
            .background(alignment: .top) { measurements }
            .geometryGroup()
            .font(.callout)
            // New York, a reading face at this size.
            .fontDesign(.serif)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
            .onTapGesture(perform: toggle)
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: isExpanded ? "Show Less" : "Show More", toggle)
    }

    private func toggle() {
        guard truncates else { return }
        HapticManager.shared.fireHaptic(.selection)
        withAnimation(.smooth(duration: 0.45)) {
            isExpanded.toggle()
        }
    }

    /// The text's whole height and its first four lines' at the width it's
    /// shown at, from hidden copies of it.
    private var measurements: some View {
        ZStack(alignment: .top) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            Text(text)
                .lineLimit(Self.collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
        }
        .hidden()
    }
}
