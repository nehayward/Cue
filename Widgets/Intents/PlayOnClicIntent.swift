import AppIntents
import CloudStorage
import Foundation
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Shortcuts action that queues an Apple Music or Spotify link to a Sonos
/// speaker or group and starts playback — the "Play on Clic" share-sheet flow,
/// usable from Apple Shortcuts.
struct PlayOnClicIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Link on Clic"
    static var isDiscoverable: Bool = true
    static var description = IntentDescription(
        "Play an Apple Music or Spotify song, album, playlist, or artist link on a Sonos speaker or group.",
        categoryName: "Playback",
        searchKeywords: ["Play", "Queue", "Music", "Sonos", "Apple Music", "Spotify", "Link"]
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(
        title: "Music Link",
        requestValueDialog: IntentDialog("Paste an Apple Music or Spotify link.")
    )
    var link: URL

    /// The speaker or group to play on. Optional in the declaration, but
    /// `perform()` always demands it via `requestValue` — a speaker is
    /// mandatory. If the speaker is grouped, playback starts across the whole
    /// group.
    @Parameter(
        title: "Speaker or Group",
        requestDisambiguationDialog: IntentDialog("Which speaker would you like to play on?")
    )
    var room: SonosDeviceEntity

    /// Where to place the content in the queue. `.automatic` matches the Play
    /// on Clic share sheet: playlists replace the queue, everything else
    /// plays now.
    @Parameter(title: "Add to Queue", default: .automatic)
    var queueOption: QueueOption

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$link) on \(\.$room)") {
            \.$queueOption
        }
    }

    init() { }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        // Validate the link up front so an empty/wrong-service URL produces a
        // helpful message instead of a downstream SonosServiceError.
        let host = link.host?.lowercased() ?? ""
        let isAppleMusic = host.contains("music.apple.com")
        let isSpotify = host.contains("spotify.com") || link.scheme?.lowercased() == "spotify"
        guard isAppleMusic || isSpotify else {
            throw IntentError.message("Paste an Apple Music or Spotify link, like https://music.apple.com/us/album/… or https://open.spotify.com/album/…")
        }

        // The speaker may have been re-grouped since the shortcut was built,
        // so resolve it to its current group at run time.
        guard let group = await resolveGroup(forRoomID: room.id) else {
            throw IntentError.message("Couldn't find “\(room.name)” on your Sonos system")
        }

        // Resolve the link. The network lookup gives the richest metadata; thes
        // offline parser is the fallback for content it can't resolve (e.g.
        // editorial playlists). Queueing only needs service, id, and type.
        var resolved = await SonosService.shared.getContent(from: link)
        if resolved == nil, let media = Self.mediaContent(from: link) {
            let fallbackTitle = Self.fallbackTitle(for: media, url: link) ?? ""
            let fallbackSubtitle = media.type == .radio ? "Station" : ""
            resolved = PlayableContent(title: fallbackTitle, subtitle: fallbackSubtitle, thumbnail: nil, artwork: nil, content: media)
        }
        guard let content = resolved else {
            throw IntentError.message("That link isn't a song, album, playlist, or artist Clic can play")
        }

        // Artists play as radio, matching the Play on Clic share sheet.
        let playable = content.content.type == .artist ? content.asArtistRadio : content

        let position: QueuePosition = queueOption.queuePosition ?? (playable.content.type.isPlaylist ? .replace : .now)
        try await SonosService.shared.queue(playable: playable, group: group, position: position)
        await SonosService.shared.play(ip: group.ip)

        #if canImport(WidgetKit)
        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif

        let dialog: IntentDialog = playable.title.isEmpty
            ? "Playing on \(room.name)"
            : "Playing \(playable.title) on \(room.name)"
        return .result(dialog: dialog)
    }

    /// Resolves a room id to its current group. Falls back to forced device
    /// discovery, since `getGroupCoordinatorWithRoom` only reads the cache and
    /// a shortcut typically runs in a cold process with nothing cached.
    private func resolveGroup(forRoomID roomID: String) async -> GroupRoom? {
        if let group = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: roomID) {
            return group
        }
        let groups = (try? await SonosService.shared.getGroups(useCache: false)) ?? []
        return groups.first { $0.rooms.contains { $0.id == roomID } }
    }
}

// MARK: - Offline link parsing

extension PlayOnClicIntent {
    /// Derives a human-readable title from the URL slug when no metadata is
    /// available. Today only Apple Music stations need this: personalized
    /// stations (`ra.u-*`) have no catalog entry and often lack scrapeable
    /// og:* tags, so the `/station/<slug>/<id>` slug is our only source.
    static func fallbackTitle(for media: MediaContent, url: URL) -> String? {
        guard media.service == .apple, media.type == .radio else { return nil }
        let pathParts = url.pathComponents.filter { $0 != "/" }
        guard pathParts.count >= 4 else { return nil }
        let slug = pathParts[2].replacingOccurrences(of: "-", with: " ")
        return slug.isEmpty ? nil : slug.capitalized
    }

    /// Best-effort offline parse of an Apple Music or Spotify link into
    /// `MediaContent`. Used when the network lookup can't resolve the link —
    /// queueing only needs the service, id, and content type.
    static func mediaContent(from url: URL) -> MediaContent? {
        if url.scheme == "spotify" { return spotifyContent(from: url) }
        guard let host = url.host?.lowercased() else { return nil }
        if host.contains("music.apple.com") { return appleMusicContent(from: url) }
        if host.contains("spotify.com") { return spotifyContent(from: url) }
        return nil
    }

    private static func appleMusicContent(from url: URL) -> MediaContent? {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // A track id supplied via `?i=` always wins.
        if let trackID = queryItems.first(where: { $0.name == "i" })?.value {
            return MediaContent(service: .apple, id: trackID, type: .track, location: url)
        }
        // Otherwise `/<storefront>/<type>/<slug?>/<id>`.
        let pathParts = url.pathComponents.filter { $0 != "/" }
        guard pathParts.count >= 3, let id = pathParts.last else { return nil }
        let type: ContentType
        switch pathParts[1] {
        case "album": type = .album
        case "song": type = .track
        case "playlist": type = .playlist
        case "artist": type = .artist
        case "station": type = .radio
        default: return nil
        }
        return MediaContent(service: .apple, id: id, type: type, location: url)
    }

    private static func spotifyContent(from url: URL) -> MediaContent? {
        // Normalise `spotify:album:<id>` URIs and `open.spotify.com/album/<id>` URLs.
        let pathParts: [String]
        if url.scheme == "spotify" {
            pathParts = url.absoluteString
                .replacingOccurrences(of: "spotify:", with: "")
                .split(separator: ":")
                .map(String.init)
        } else {
            pathParts = url.pathComponents.filter { $0 != "/" }
        }
        guard pathParts.count >= 2 else { return nil }
        let type: ContentType
        switch pathParts[0] {
        case "track": type = .track
        case "album": type = .album
        case "playlist": type = .playlist
        case "artist": type = .artist
        default: return nil
        }
        return MediaContent(service: .spotify, id: pathParts[1], type: type, location: url)
    }
}

// MARK: - Artist radio

private extension PlayableContent {
    /// Same content re-typed as artist radio, matching the share sheet's
    /// "Play Radio" action for artist links.
    var asArtistRadio: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail,
            artwork: artwork,
            content: MediaContent(
                service: content.service,
                id: content.id,
                type: .artistRadio,
                location: content.location
            )
        )
    }
}
