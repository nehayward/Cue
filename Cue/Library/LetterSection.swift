import SwiftUI

/// One alphabetical group in a plain list: a letter heading and its rows.
///
/// On Mac Catalyst the system's pinned section header and `sectionIndexLabel`
/// index draw an overlay across the rows while scrolling, so there the letter
/// is our own non-pinned heading row, and the index is `letterIndex(_:)`'s
/// bar instead. Everywhere else it keeps the system header and index.
struct LetterSection<Content: View>: View {
    let letter: String
    @ViewBuilder var content: Content

    var body: some View {
        #if targetEnvironment(macCatalyst)
        Section {
            Text(letter)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .id(letterSectionAnchor(letter))
            content
        }
        #else
        Section(header: Text(letter)) {
            content
        }
        .sectionIndex(letter)
        #endif
    }
}

/// The scroll id of a `LetterSection`'s heading row. Prefixed so it can't
/// collide with a row's own id.
func letterSectionAnchor(_ letter: String) -> String {
    "letter-section-\(letter)"
}

extension View {
    /// A letter index along the trailing edge of a list built from
    /// `LetterSection`s, which jumps to a section on click or drag. Catalyst
    /// only: the other platforms use the system index.
    @ViewBuilder
    func letterIndex(_ letters: [String]) -> some View {
        #if targetEnvironment(macCatalyst)
        ScrollViewReader { proxy in
            self
                // Keeps the rows' trailing menus out from under the bar.
                .contentMargins(.trailing, letters.count > 1 ? LetterIndexBar.width + 8 : 0, for: .scrollContent)
                .overlay(alignment: .trailing) {
                    if letters.count > 1 {
                        LetterIndexBar(letters: letters) { letter in
                            proxy.scrollTo(letterSectionAnchor(letter), anchor: .top)
                        }
                        .padding(.trailing, 4)
                    }
                }
        }
        #else
        self
        #endif
    }
}

/// A column of letters with no background. Dragging across it scrubs through
/// the sections, jumping each time the pointer reaches a new letter; only the
/// letter under the pointer is highlighted.
struct LetterIndexBar: View {
    static let width: CGFloat = 22
    private static let rowHeight: CGFloat = 16
    private static let spacing: CGFloat = 2
    private static let verticalPadding: CGFloat = 8

    let letters: [String]
    let onSelect: (String) -> Void

    @State private var active: String?

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.caption2.weight(letter == active ? .heavy : .semibold))
                    .foregroundStyle(letter == active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .scaleEffect(letter == active ? 1.3 : 1)
                    .frame(width: Self.width, height: Self.rowHeight)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onSelect(letter) }
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in select(at: value.location.y) }
                .onEnded { _ in
                    // Held a moment after release so a click shows which
                    // letter it landed on.
                    let released = active
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        if active == released { active = nil }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section Index")
    }

    private func select(at y: CGFloat) {
        let step = Self.rowHeight + Self.spacing
        let index = Int((y - Self.verticalPadding) / step)
        let letter = letters[min(max(index, 0), letters.count - 1)]
        guard letter != active else { return }
        active = letter
        onSelect(letter)
    }
}
