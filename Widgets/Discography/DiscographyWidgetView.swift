import Defaults
import SwiftUI
import WidgetKit

/// The discography widget, by size: four covers round the artist's photo
/// on a small one, a row under the artist on a medium, and a grid with
/// titles and years on the rest, a new release leading it on its own.
struct DiscographyWidgetView: View {
    let entry: DiscographyEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .environment(\.shelfStyle, entry.style)
            // Taps off a cover: Cue itself.
            .widgetURL(URL(string: "cue://"))
            .containerBackground(for: .widget) {
                DiscographyBackground(release: entry.artist?.releases.first)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let artist = entry.artist, !artist.releases.isEmpty {
            switch family {
            case .systemSmall:
                SmallDiscography(entry: entry, artist: artist)
            case .systemMedium:
                RowDiscography(entry: entry, artist: artist)
            default:
                GridDiscography(entry: entry, artist: artist)
            }
        } else {
            DiscographyMessage(entry: entry, isCompact: family == .systemSmall)
        }
    }
}

// MARK: - Sizes

/// Four covers, two by two, the artist's photo between them.
private struct SmallDiscography: View {
    let entry: DiscographyEntry
    let artist: DiscographyArtist

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 6
            let inset: CGFloat = 12
            let side = (min(proxy.size.width, proxy.size.height) - inset * 2 - gap) / 2
            let releases = Array(artist.releases.prefix(4))
            VStack(spacing: gap) {
                ForEach([0, 2], id: \.self) { start in
                    HStack(spacing: gap) {
                        ForEach(releases.dropFirst(start).prefix(2)) { release in
                            ReleaseCoverTile(release: release, artist: artist, entry: entry, side: side, showsBadge: false)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay {
                ArtistPhoto(artist: artist, size: side * 0.62)
            }
        }
    }
}

/// The artist, then a row of covers.
private struct RowDiscography: View {
    let entry: DiscographyEntry
    let artist: DiscographyArtist

    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        GeometryReader { proxy in
            let layout = DiscographyLayout(size: proxy.size, margins: margins)
            let gap: CGFloat = 10
            let tallest = layout.height - DiscographyLayout.headerHeight - DiscographyLayout.headerGap
            // As many as fill the row edge to edge, none taller than the room.
            let count = max(3, Int(((layout.width + gap) / (tallest + gap)).rounded(.up)))
            let side = min(tallest, (layout.width - CGFloat(count - 1) * gap) / CGFloat(count))
            VStack(alignment: .leading, spacing: DiscographyLayout.headerGap) {
                DiscographyHeader(entry: entry, artist: artist)
                HStack(spacing: gap) {
                    ForEach(artist.releases.prefix(count)) { release in
                        ReleaseCoverTile(release: release, artist: artist, entry: entry, side: side)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, layout.inset)
            .padding(.top, layout.top)
            .padding(.bottom, layout.bottom)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

/// The artist, their newest release on its own (New Release while it's
/// recent), then as many rows of covers with their titles and years as
/// fit, newest first.
private struct GridDiscography: View {
    let entry: DiscographyEntry
    let artist: DiscographyArtist

    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        GeometryReader { proxy in
            let layout = DiscographyLayout(size: proxy.size, margins: margins)
            let gap: CGFloat = 12
            let columns = max(2, Int((layout.width + gap) / (92 + gap)))
            let side = (layout.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let lead = artist.releases.first
            let leadSide = min(layout.width * 0.38, 136)
            let above = DiscographyLayout.headerHeight + DiscographyLayout.headerGap + (lead == nil ? 0 : leadSide + 18)
            let cell = side + ReleaseCaption.height
            let rows = max(0, Int((layout.height - above + gap) / (cell + gap)))
            let rest = Array(artist.releases.dropFirst(lead == nil ? 0 : 1).prefix(columns * rows))
            VStack(alignment: .leading, spacing: 0) {
                DiscographyHeader(entry: entry, artist: artist)
                    .padding(.bottom, DiscographyLayout.headerGap)
                if let lead {
                    LeadRelease(release: lead, artist: artist, entry: entry, side: leadSide)
                        .padding(.bottom, 18)
                }
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(Array(stride(from: 0, to: rest.count, by: columns)), id: \.self) { start in
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(rest[start ..< min(start + columns, rest.count)]) { release in
                                VStack(alignment: .leading, spacing: 0) {
                                    ReleaseCoverTile(release: release, artist: artist, entry: entry, side: side)
                                    ReleaseCaption(release: release, date: entry.date)
                                }
                                .frame(width: side, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, layout.inset)
            .padding(.top, layout.top)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

/// The room inside the widget's margins, which `contentMarginsDisabled`
/// leaves to the views.
private struct DiscographyLayout {
    static let headerHeight: CGFloat = 34
    static let headerGap: CGFloat = 12

    let inset: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(size: CGSize, margins: EdgeInsets) {
        inset = margins.leading > 0 ? margins.leading : 16
        top = margins.top > 0 ? margins.top : 16
        bottom = margins.bottom > 0 ? margins.bottom : 16
        width = size.width - inset * 2
        height = size.height - top - bottom
    }
}

// MARK: - Parts

/// The artist's photo and name, how many releases and where, Play's
/// speaker, and Cue's glyph.
private struct DiscographyHeader: View {
    let entry: DiscographyEntry
    let artist: DiscographyArtist

    var body: some View {
        HStack(spacing: 10) {
            ArtistPhoto(artist: artist, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(artist.name)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let speaker = entry.speaker {
                SpeakerLabel(name: speaker, color: .secondary)
            }
            CueGlyph()
        }
        .frame(height: DiscographyLayout.headerHeight)
    }

    private var subtitle: String {
        let count = artist.releases.count
        let noun = entry.onlyAlbums ? (count == 1 ? "album" : "albums") : (count == 1 ? "release" : "releases")
        return "\(count) \(noun) · \(DiscographyService(artistID: artist.id).name)"
    }
}

/// The newest release: its cover, what it is, and Play. Out within the last
/// few months, or coming, it's shown off: New Release in Cue's green, the
/// artist's photo on the cover's corner.
private struct LeadRelease: View {
    let release: DiscographyArtist.Release
    let artist: DiscographyArtist
    let entry: DiscographyEntry
    let side: CGFloat

    var body: some View {
        let isNew = release.isNew(at: entry.date)
        HStack(alignment: .center, spacing: 16) {
            ReleaseCoverTile(release: release, artist: artist, entry: entry, side: side, showsBadge: false)
                .overlay(alignment: .bottomTrailing) {
                    if isNew {
                        ArtistPhoto(artist: artist, size: side * 0.32)
                            .offset(x: side * 0.08, y: side * 0.08)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                eyebrowLabel(isNew: isNew)
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .textCase(.uppercase)
                    .widgetAccentable()
                Text(release.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let released = release.released {
                    Text(released, format: .dateTime.day().month(.wide).year())
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                PlayPauseCapsule(book: release.book(by: artist), isPlaying: entry.isPlaying(release), isRoomy: side >= 120)
            }
            .frame(height: side, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func eyebrowLabel(isNew: Bool) -> some View {
        if isNew {
            Label(eyebrow, systemImage: release.isUpcoming(at: entry.date) ? "calendar" : "sparkles")
                .foregroundStyle(Color("Accent"))
        } else {
            Text(entry.onlyAlbums ? "Latest Album" : "Latest Release")
                .foregroundStyle(.secondary)
        }
    }

    private var eyebrow: String {
        guard release.isUpcoming(at: entry.date), let released = release.released else { return "New Release" }
        return "Out \(released.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// A release's cover: Play or its page on a tap, as the widget is set, the
/// player's mark on the album in it, and New on one just out.
private struct ReleaseCoverTile: View {
    let release: DiscographyArtist.Release
    let artist: DiscographyArtist
    let entry: DiscographyEntry
    let side: CGFloat
    var showsBadge = true

    var body: some View {
        let radius = max(side * 0.07, 4)
        BookTap(book: release.book(by: artist)) {
            ReleaseCover(release: release)
                .frame(width: side, height: side)
                .clipShape(.rect(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
                .overlay(alignment: .topLeading) {
                    if let mark = entry.style.coverMark(isPlaying: entry.isPlaying(release), isLoaded: entry.isLoaded(release)) {
                        CoverMark(symbol: mark, size: max(side * 0.26, 18))
                            .padding(max(side * 0.05, 4))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if showsBadge, release.isNew(at: entry.date) {
                        NewBadge(isUpcoming: release.isUpcoming(at: entry.date))
                            .padding(max(side * 0.06, 4))
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
    }
}

/// "New", or "Soon" for one not out yet, in Cue's green.
private struct NewBadge: View {
    let isUpcoming: Bool

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(isUpcoming ? "Soon" : "New")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(renderingMode == .fullColor ? Color.white : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(renderingMode == .fullColor ? Color("Accent") : Color.primary.opacity(0.25), in: .capsule)
            .widgetAccentable()
    }
}

/// A release's title and year, under its cover.
private struct ReleaseCaption: View {
    static let height: CGFloat = 36

    let release: DiscographyArtist.Release
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(release.title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .lineLimit(1)
            if let released = release.released {
                Text(released, format: .dateTime.year())
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 5)
        .frame(height: Self.height, alignment: .top)
    }
}

/// The cover the widget keeps, else a plain tile with a note on it, as
/// Music draws an album without art.
private struct ReleaseCover: View {
    let release: DiscographyArtist.Release

    var body: some View {
        Color.clear
            .overlay {
                if let name = release.cover, let image = BookCoverImages.image(named: name, in: .discography) {
                    Image(uiImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                } else {
                    GeometryReader { proxy in
                        LinearGradient(colors: [Color(uiColor: .systemGray4), Color(uiColor: .systemGray5)], startPoint: .top, endPoint: .bottom)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: proxy.size.width * 0.32, weight: .medium))
                                    .foregroundStyle(Color(uiColor: .systemGray))
                            }
                    }
                }
            }
            .clipped()
    }
}

/// The artist's photo in a circle, ringed; a plain one before there's one.
struct ArtistPhoto: View {
    let artist: DiscographyArtist
    let size: CGFloat

    var body: some View {
        Color.clear
            .overlay {
                if let name = artist.photo, let image = BookCoverImages.image(named: name, in: .discography) {
                    Image(uiImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                } else {
                    Color(uiColor: .systemGray4)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: size * 0.46))
                                .foregroundStyle(Color(uiColor: .systemGray))
                                .offset(y: size * 0.04)
                        }
                }
            }
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: max(size * 0.045, 1.5))
            }
            .shadow(color: .black.opacity(0.25), radius: size * 0.08, y: size * 0.03)
            .accessibilityHidden(true)
    }
}

/// The newest cover blurred under a frost of the system background, light
/// or dark with it, as the shelves' Glass look; the background alone
/// before there's a cover.
private struct DiscographyBackground: View {
    let release: DiscographyArtist.Release?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let release, release.cover != nil {
                ReleaseCover(release: release)
                    .blur(radius: 50, opaque: true)
                    .saturation(1.4)
                Color(uiColor: .systemBackground)
                    .opacity(isDark ? 0.5 : 0.6)
            }
            LinearGradient(colors: [.white.opacity(isDark ? 0.1 : 0.3), .clear], startPoint: .topLeading, endPoint: .center)
        }
    }
}

/// What the widget says with no releases to show: choose an artist, open
/// Cue for a Plex one, or Apple Music not answering.
private struct DiscographyMessage: View {
    let entry: DiscographyEntry
    let isCompact: Bool

    var body: some View {
        VStack(spacing: isCompact ? 4 : 6) {
            Image(systemName: "music.mic")
                .font(isCompact ? .title3 : .title2)
                .widgetAccentable()
            if !isCompact {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
            }
            Text(message)
                .font(.system(.caption, design: .rounded))
                .opacity(0.75)
                .lineLimit(isCompact ? 4 : 3)
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        entry.chosen?.name ?? "Choose an Artist"
    }

    private var message: String {
        guard let chosen = entry.chosen else {
            return "Touch and hold, then Edit Widget to choose an artist."
        }
        if entry.artist != nil {
            return "No albums yet."
        }
        return switch DiscographyService(artistID: chosen.id) {
        case .appleMusic: "Apple Music isn't answering. Their albums will be here once it does."
        case .plex: "Open Cue to put \(chosen.name)'s albums here."
        }
    }
}

extension DiscographyArtist.Release {
    /// The release as the shelves' taps and Play take an item.
    func book(by artist: DiscographyArtist) -> ShelfBook {
        ShelfBook(id: id, title: title, author: artist.name, fraction: nil, remaining: nil, duration: 0, isFinished: false, isDownloaded: false, cover: nil)
    }
}
