import SonosKit
import SwiftUI

/// One row of the Radio tab: a titled run of stations in a grid, headed by
/// a link to the full list.
struct RadioStationsSection: View {
    /// How the stations are drawn.
    enum Style {
        /// Logo and name side by side. TuneIn's logos rarely say which
        /// station they are, so the name has to be there.
        case rows
        /// The cover alone. Apple's station art carries the station's name,
        /// so a title beside it only repeated it, cut short.
        case artwork
    }

    let title: String
    /// Where the stations come from — "TuneIn" — under the title, since the
    /// tab mixes sources that each have their own rows.
    var caption: String? = nil
    let items: [PlayableContent]
    /// The full list the title opens.
    let seeAll: RouterDestination
    var style: Style = .rows
    /// Stations shown in the grid before the "see all" link. Six fills the
    /// grid's rows at every column count it uses.
    var previewCount = 6

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Section {
            RadioSectionHeader(title: title, caption: caption, destination: seeAll)

            switch style {
            case .rows:
                rows
            case .artwork:
                artwork
            }
        }
        .listRowInsets(.default)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowSpacing(0)
    }

    private var rows: some View {
        LazyVGrid(columns: RadioGrid.columns(sizeClass == .compact ? 2 : 3), spacing: RadioGrid.spacing) {
            ForEach(items.prefix(previewCount)) { item in
                // Every station is radio, so "Radio" under each name said
                // nothing; the name gets the second line instead.
                PlayableContentRowView(item: item, hideSubtitle: true)
                    .buttonStyle(.plain)
                    .clipShape(.rect(cornerRadius: RadioGrid.cornerRadius))
                    .geometryGroup()
            }
        }
    }

    /// Three covers to a row on a phone, six where there's room: either way
    /// the six live stations fill whole rows.
    private var artwork: some View {
        let columns = sizeClass == .compact ? 3 : 6
        // A phone's tile is about 130pt, a wide window's at most about 180;
        // decoded no bigger than that, scaled for the screen's density the
        // way the album wall does.
        let artworkSize = Double(sizeClass == .compact ? 130 : 180) * min(displayScale, 3) / 3
        return LazyVGrid(columns: RadioGrid.columns(columns), spacing: RadioGrid.spacing) {
            ForEach(items.prefix(previewCount)) { item in
                PlayableCardView(
                    item: item,
                    artworkOnly: true,
                    artworkSize: artworkSize,
                    artworkCornerRadius: RadioGrid.cornerRadius
                )
                .overlay {
                    // A hairline, so a white cover still has an edge on a
                    // white screen.
                    RoundedRectangle(cornerRadius: RadioGrid.cornerRadius, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// A Radio tab section's title: what it is, where it comes from, and —
/// when there's more than the section shows — a link to the rest. Every
/// section uses it, so the tab's headings all read alike. A row rather
/// than a section header, which a plain list pins while it scrolls.
struct RadioSectionHeader: View {
    let title: String
    var caption: String? = nil
    var destination: RouterDestination? = nil

    @Environment(Router.self) private var router

    var body: some View {
        if let destination {
            // A button with its own chevron beside the title, not a
            // `NavigationLink`, whose chevron sits at the row's far edge
            // and centres on the caption as well as the title.
            Button {
                router.navigate(to: destination)
            } label: {
                label(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows all \(title)")
        } else {
            label(showsChevron: false)
        }
    }

    private func label(showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                if showsChevron {
                    Image(systemName: "chevron.forward")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .fontDesign(.rounded)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The measurements the Radio tab's grids share, so station rows, covers
/// and directory tiles line up with each other.
enum RadioGrid {
    static let spacing: CGFloat = 10
    static let cornerRadius: CGFloat = 8

    static func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}
