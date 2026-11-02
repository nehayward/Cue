import SwiftUI

/// A word looked up in a book's transcript, marked as Read Along marks it
/// in its line, over the words around it there with the word picked out.
/// Opacities of primary, not `.secondary`, for the player's glass sheets.
struct BookWordLabel: View {
    let lookup: BookWordLookups.Lookup

    /// Read Along's mark on a word looked up.
    static let highlight = Color.yellow.opacity(0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lookup.term)
                .foregroundStyle(.primary)
                .padding(.horizontal, 3)
                .background(Self.highlight, in: .rect(cornerRadius: 3))
            Text("\(Text(verbatim: lookup.before))\(Text(verbatim: lookup.term).foregroundStyle(.primary))\(Text(verbatim: lookup.after))")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.6))
                .lineLimit(2)
        }
    }
}
