import AppIntents
import Defaults
import SwiftUI
import WidgetKit

/// One artist's albums, newest first, every Home Screen size: a grid of
/// covers under the artist's photo, a release out within the last few
/// months leading as New Release with the photo on its cover.
///
/// Edit Widget picks the service and the artist. An Apple Music artist the
/// widget reads itself from Apple's public catalog (`AppleMusicArtists`),
/// every few hours, so a new release turns up with Cue closed; a Plex
/// artist's albums Cue writes (`DiscographyWidgetPublisher`), since only Cue
/// can reach the server. A tap plays an album or opens it, through the album
/// shelf's intent and links.
struct DiscographyWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: DiscographyArtist.widgetKind, intent: DiscographyConfigurationIntent.self, provider: DiscographyProvider()) { entry in
            DiscographyWidgetView(entry: entry)
        }
        .configurationDisplayName("Discography")
        .description("An artist's albums, newest first, with their new releases as they come out.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }

    private static var families: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        #endif
        return families
    }
}

/// What a discography widget shows and does, chosen in its Edit Widget sheet.
struct DiscographyConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Discography"
    static let description = IntentDescription("Shows an artist's albums, newest first.")

    @Parameter(title: "Service", default: .appleMusic)
    var service: DiscographyService

    /// Each service its own artist, so a change of service shows that
    /// service's, empty until one's chosen (Edit Widget can't clear one
    /// setting as another changes), and changing back brings the other back.
    @Parameter(title: "Artist")
    var artist: WidgetArtist?

    @Parameter(title: "Artist")
    var plexArtist: PlexWidgetArtist?

    @Parameter(title: "Show", default: .studioAlbums)
    var releases: DiscographyReleases

    @Parameter(title: "Action", default: .playAlbum)
    var action: AlbumWidgetAction

    @Parameter(title: "Play in Background", description: "Plays without opening Cue.", default: true)
    var playsInBackground: Bool

    /// The artist for the service chosen.
    var chosenArtist: WidgetArtist? {
        switch service {
        case .appleMusic: artist
        case .plex: plexArtist?.artist
        }
    }

    /// The service's own artist; Play in Background only for Play Album.
    static var parameterSummary: some ParameterSummary {
        When(\.$service, .equalTo, .appleMusic) {
            When(\.$action, .equalTo, .playAlbum) {
                Summary {
                    \.$service
                    \.$artist
                    \.$releases
                    \.$action
                    \.$playsInBackground
                }
            } otherwise: {
                Summary {
                    \.$service
                    \.$artist
                    \.$releases
                    \.$action
                }
            }
        } otherwise: {
            When(\.$action, .equalTo, .playAlbum) {
                Summary {
                    \.$service
                    \.$plexArtist
                    \.$releases
                    \.$action
                    \.$playsInBackground
                }
            } otherwise: {
                Summary {
                    \.$service
                    \.$plexArtist
                    \.$releases
                    \.$action
                }
            }
        }
    }
}

/// Where the artist's albums come from.
enum DiscographyService: String, AppEnum, CaseIterable {
    case appleMusic
    case plex

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Service"
    static let caseDisplayRepresentations: [DiscographyService: DisplayRepresentation] = [
        .appleMusic: "Apple Music",
        .plex: "Plex",
    ]

    /// What its artists' keys start with.
    var prefix: String {
        switch self {
        case .appleMusic: AppleMusicArtists.prefix
        case .plex: "plex|"
        }
    }

    var name: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .plex: "Plex"
        }
    }

    init(artistID: String) {
        self = artistID.hasPrefix(Self.plex.prefix) ? .plex : .appleMusic
    }
}

/// An Apple Music artist for Edit Widget's Artist, and the artist a widget
/// shows whatever its service. Each service's Artist has a type and query
/// of its own: a query told the service through `@IntentParameterDependency`
/// was told nothing on a device, and Plex's list came up empty.
struct WidgetArtist: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Artist"
    static let defaultQuery = WidgetArtistQuery()

    /// The artist's key: `apple|<catalog id>` or `plex|<id>`.
    let id: String
    let name: String
    /// The genre, from Apple Music's search.
    var detail = ""
    /// Their photo on Apple Music, for a search result.
    var photoURL: URL?

    /// With the photo the widget keeps once it has read the artist, else
    /// the one a search found.
    var displayRepresentation: DisplayRepresentation {
        let kept = DiscographyArtist.load(id: id)?.photo
            .flatMap(DiscographyArtist.imageURL(named:))
            .flatMap { try? Data(contentsOf: $0) }
        let image = kept.map { DisplayRepresentation.Image(data: $0, isTemplate: false) }
            ?? photoURL.map { DisplayRepresentation.Image(url: $0, isTemplate: false) }
            ?? DisplayRepresentation.Image(systemName: "music.mic")
        let subtitle = [detail, DiscographyService(artistID: id).name].filter { !$0.isEmpty }.joined(separator: " · ")
        return DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)", image: image)
    }
}

/// Apple Music's artists, its whole catalog as you search, those widgets
/// have shown before you type.
struct WidgetArtistQuery: EntityStringQuery {
    /// Always an artist for each id, so a choice holds with nothing to look
    /// it up in (offline).
    func entities(for identifiers: [String]) async throws -> [WidgetArtist] {
        var artists: [WidgetArtist] = []
        for id in identifiers {
            if let kept = DiscographyArtist.load(id: id) {
                artists.append(WidgetArtist(id: id, name: kept.name))
            } else if let found = await AppleMusicArtists.artist(named: id) {
                artists.append(found)
            } else {
                artists.append(WidgetArtist(id: id, name: "Artist"))
            }
        }
        return artists
    }

    func entities(matching string: String) async throws -> IntentItemCollection<WidgetArtist> {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return try await suggestedEntities() }
        return IntentItemCollection(items: await AppleMusicArtists.search(query))
    }

    func suggestedEntities() async throws -> IntentItemCollection<WidgetArtist> {
        let shown = DiscographyArtist.kept()
            .filter { $0.id.hasPrefix(AppleMusicArtists.prefix) }
            .map { WidgetArtist(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return IntentItemCollection(items: shown)
    }
}

/// A Plex artist for Edit Widget's Artist with Plex chosen.
struct PlexWidgetArtist: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Artist"
    static let defaultQuery = PlexArtistQuery()

    /// The artist's key, `plex|<id>`.
    let id: String
    let name: String

    var artist: WidgetArtist {
        WidgetArtist(id: id, name: name)
    }

    var displayRepresentation: DisplayRepresentation {
        artist.displayRepresentation
    }
}

/// Every artist on the Plex server, as Cue last listed them
/// (`DiscographyWidgetPublisher`), searchable by name.
struct PlexArtistQuery: EntityStringQuery {
    /// Always an artist for each id, so a choice holds before Cue lists
    /// them again.
    func entities(for identifiers: [String]) async throws -> [PlexWidgetArtist] {
        let listed = Self.artists()
        return identifiers.map { id in
            listed.first { $0.id == id } ?? PlexWidgetArtist(id: id, name: DiscographyArtist.load(id: id)?.name ?? "Artist")
        }
    }

    func entities(matching string: String) async throws -> IntentItemCollection<PlexWidgetArtist> {
        let query = string.trimmingCharacters(in: .whitespaces)
        return IntentItemCollection(items: Self.artists().filter { query.isEmpty || $0.name.localizedStandardContains(query) })
    }

    func suggestedEntities() async throws -> IntentItemCollection<PlexWidgetArtist> {
        IntentItemCollection(items: Self.artists())
    }

    private static func artists() -> [PlexWidgetArtist] {
        (BookShelfWidgetState.Catalog.load(.discography)?.books ?? []).map { PlexWidgetArtist(id: $0.id, name: $0.title) }
    }
}

// MARK: - Timeline

struct DiscographyEntry: TimelineEntry {
    let date: Date
    /// The artist and their releases; nil before they're read.
    let artist: DiscographyArtist?
    /// Who was picked, while their releases aren't in.
    var chosen: WidgetArtist?
    let style: ShelfStyle
    /// Studio albums alone (`DiscographyReleases.studioAlbums`).
    var onlyAlbums = false
    /// The album in the player, by key, and whether it plays.
    var albumInPlayer: String?
    var isPlaying = false
    /// The Sonos group Play goes to.
    var speaker: String?

    func isPlaying(_ release: DiscographyArtist.Release) -> Bool {
        isPlaying && isLoaded(release)
    }

    /// Whether `release` is the album in the player. A Plex song on a
    /// speaker names its album by the bare rating key, the album's own key
    /// by its full id (`…%3A<rating key>`), so a Plex key counts by its
    /// rating key.
    func isLoaded(_ release: DiscographyArtist.Release) -> Bool {
        guard let albumInPlayer else { return false }
        if albumInPlayer == release.id { return true }
        guard let playing = Self.ratingKey(albumInPlayer) else { return false }
        return playing == Self.ratingKey(release.id)
    }

    private static func ratingKey(_ key: String) -> String? {
        let prefix = DiscographyService.plex.prefix
        guard key.hasPrefix(prefix) else { return nil }
        let id = key.dropFirst(prefix.count)
        return (id.removingPercentEncoding ?? String(id)).components(separatedBy: ":").last
    }

    var relevance: TimelineEntryRelevance? {
        if artist?.releases.contains(where: isPlaying) == true { return TimelineEntryRelevance(score: 80) }
        if artist?.releases.first?.isNew(at: date) == true { return TimelineEntryRelevance(score: 40) }
        return nil
    }
}

struct DiscographyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DiscographyEntry {
        DiscographyEntry(date: .now, artist: .sample, style: Self.style(for: DiscographyConfigurationIntent()))
    }

    /// The gallery shows an artist of the listener's own: one a widget has
    /// shown, else the artist of the Apple Music album played last; the
    /// made-up one only with neither.
    func snapshot(for configuration: DiscographyConfigurationIntent, in context: Context) async -> DiscographyEntry {
        if context.isPreview, configuration.chosenArtist == nil {
            guard let artist = await Self.galleryArtist() else { return placeholder(in: context) }
            return DiscographyEntry(date: .now, artist: artist, style: Self.style(for: configuration))
        }
        return await entry(for: configuration, in: context)
    }

    private static func galleryArtist() async -> DiscographyArtist? {
        if let shown = DiscographyArtist.kept().max(by: { $0.readAt < $1.readAt }), !shown.releases.isEmpty {
            return shown
        }
        let played = BookShelfWidgetState.load(.albums)?.albums(on: .recentlyPlayed) ?? []
        for album in played.prefix(5) {
            guard let artistID = await AppleMusicArtists.artistID(ofAlbum: album.id) else { continue }
            return await AppleMusicArtists.discography(of: artistID)
        }
        return nil
    }

    /// Read again every few hours, for new releases, or in a quarter of an
    /// hour when the artist or covers it shows didn't come (no network);
    /// Cue reloads it as the player changes, which reads what's kept.
    func timeline(for configuration: DiscographyConfigurationIntent, in context: Context) async -> Timeline<DiscographyEntry> {
        let entry = await entry(for: configuration, in: context)
        let isWhole = configuration.chosenArtist == nil
            || entry.artist.map { !$0.releases.prefix(Self.coversShown).contains { $0.cover == nil } } ?? false
        let wait = isWhole ? AppleMusicArtists.refreshAfter : 15 * 60
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(wait)))
    }

    /// The covers the widest widget shows.
    private static let coversShown = 24

    private func entry(for configuration: DiscographyConfigurationIntent, in context: Context) async -> DiscographyEntry {
        let style = Self.style(for: configuration)
        let onlyAlbums = configuration.releases == .studioAlbums
        guard let chosen = configuration.chosenArtist else {
            return DiscographyEntry(date: .now, artist: nil, style: style, onlyAlbums: onlyAlbums)
        }
        // For Cue to write what only it can read: a Plex artist's albums,
        // and which of an Apple Music artist's releases Apple counts as
        // albums.
        if !context.isPreview {
            BookShelfWidgetState.noteChosen([chosen.id], in: .discography)
        }
        var artist: DiscographyArtist?
        if chosen.id.hasPrefix(AppleMusicArtists.prefix) {
            artist = await AppleMusicArtists.discography(of: chosen.id)
        } else {
            artist = DiscographyArtist.load(id: chosen.id)
        }
        if var read = artist {
            let listed = DiscographyArtist.albumList(for: chosen.id).map { Set($0.ids.map { "\(AppleMusicArtists.prefix)\($0)" }) }
            func shown(_ artist: DiscographyArtist) -> [DiscographyArtist.Release] {
                onlyAlbums ? artist.studioAlbums(listedBy: listed) : artist.everyRelease()
            }
            var releases = shown(read)
            // Their covers, which the read fetched only for the newest
            // releases: an artist's albums can be far older than their
            // latest compilations and remixes.
            if chosen.id.hasPrefix(AppleMusicArtists.prefix), releases.prefix(Self.coversShown).contains(where: { $0.cover == nil }) {
                read = await AppleMusicArtists.writeCovers(of: read, for: Set(releases.prefix(Self.coversShown).map(\.id)))
                releases = shown(read)
            }
            artist?.releases = releases
        }
        let player = BookShelfWidgetState.load(.albums)
        return DiscographyEntry(
            date: .now,
            artist: artist,
            chosen: chosen,
            style: style,
            onlyAlbums: onlyAlbums,
            albumInPlayer: player?.albumInPlayer,
            isPlaying: player?.albumInPlayerIsPlaying == true,
            speaker: player?.speaker
        )
    }

    private static func style(for configuration: DiscographyConfigurationIntent) -> ShelfStyle {
        ShelfStyle(kind: .albums, look: .glass, action: configuration.action.action, playsInBackground: configuration.playsInBackground, showsProgress: false)
    }
}

// MARK: - The gallery's artist

extension DiscographyArtist {
    /// What the widget gallery shows: a made-up artist, covers drawn for
    /// their albums, the newest just out.
    static let sample: DiscographyArtist = {
        let day: TimeInterval = 24 * 3600
        let albums: [(String, TimeInterval)] = [
            ("Afterglow", 12), ("Blue Hour (Live)", 260), ("Static Hearts", 610), ("Glass Houses", 1_150),
            ("Paper Moons", 1_520), ("Slow Tide", 1_980), ("Late Bloom", 2_410), ("Open Road", 2_900),
            ("Small Victories", 3_350), ("Undertow", 3_800), ("Northern Lights", 4_300), ("Wildflower Year", 4_750),
        ]
        return DiscographyArtist(
            id: "sample-artist",
            name: "Juniper Lane",
            photo: nil,
            releases: albums.enumerated().map { index, album in
                Release(id: "sample-album|\(index)", title: album.0, released: .now.addingTimeInterval(-album.1 * day), cover: nil)
            },
            readAt: .now
        )
    }()
}
