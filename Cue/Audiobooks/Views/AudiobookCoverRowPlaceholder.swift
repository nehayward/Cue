import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A row of covers still on its way: grey squares the size of the covers,
/// so the row takes its room before its books arrive.
struct AudiobookCoverRowPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.fill.tertiary)
                        .frame(width: AudiobookCoverRow.coverSize, height: AudiobookCoverRow.coverSize)
                    Text(verbatim: "Book title")
                        .font(.footnote)
                    Text(verbatim: "Author")
                        .font(.caption)
                }
                .frame(width: AudiobookCoverRow.coverSize, alignment: .leading)
            }
        }
        .redacted(reason: .placeholder)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
