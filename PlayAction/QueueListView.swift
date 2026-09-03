import SwiftUI
import Defaults
import SonosKit
import MusicSearchKit
import VibesDS
import OSLog

struct QueueListView: View {
    private let sonosService: SonosService = .shared
    private let playHistoryService = PlayHistoryService.shared
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()

    @State private var content: PlayableContent?
    @State private var destination: PlayDestination = .device
    @State private var didRestoreDestination = false
    @State private var groupVolume: Double = 0
    @State private var isQueueing = false
    @State private var setVolume = false
    @State private var queuePosition: QueuePosition = .now

    var viewModel: ViewModel
    var context: NSExtensionContext?
    var openURL: ((URL) -> Void)?

    init(viewModel: ViewModel, context: NSExtensionContext? = nil, openURL: ((URL) -> Void)?) {
        self.viewModel = viewModel
        self.context = context
        self.openURL = openURL
    }

    // MARK: - Derived state

    private var isArtist: Bool {
        content?.content.type == .artist
    }

    /// Every group, in the user's chosen sort order. A lone speaker is a group
    /// of one in Sonos, so this is also the full list of rooms.
    private var groups: [GroupRoom] {
        sonosService.sorted
    }

    private var selectedGroup: GroupRoom? {
        guard let id = destination.groupID else { return nil }
        return groups.first { $0.coordinatorID == id }
    }

    /// Whether the phone could take this content at all. `LocalPlaybackService`
    /// in the main app is the real authority — it re-checks and falls back to
    /// the room picker when a track turns out to be unplayable after the fact
    /// (a Plex track with no stream URL, Apple without a subscription). This is
    /// deliberately the looser test, so Device is only ruled out for content
    /// that can *never* play here: radio, artists, and the services with no
    /// local backend.
    private var canPlayOnDevice: Bool {
        guard let content else { return false }
        return switch (content.content.service, content.content.type) {
        case (.apple, .track), (.apple, .libraryTrack), (.apple, .album), (.apple, .libraryAlbum):
            true
        case (.plex, .track), (.plex, .album):
            true
        default:
            false
        }
    }

    private var canPlay: Bool {
        switch destination {
        case .device: canPlayOnDevice
        case .group: selectedGroup != nil
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            queueContent
                .toolbar { toolbarContent }
                .navigationBarTitleDisplayMode(.inline)
                .background {
                    Button("", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
        }
        .tint(.primary)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.callout.weight(.semibold))
            }
            .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { dismiss(opening: openInCueURL) } label: {
                    Label("Open in Cue", systemImage: "play.circle")
                }
                .disabled(viewModel.url == nil)

                Button { dismiss(opening: viewInCueURL) } label: {
                    Label("View in Cue", systemImage: "info.circle")
                }
                .disabled(viewModel.url == nil)
            } label: {
                Image(systemName: "ellipsis").font(.callout.weight(.semibold))
            }
        }
    }

    /// Prefers the resolved content's `cue://play/...` URL when we have it; otherwise
    /// hands the raw shared URL to the main app via `cue://resolve?url=...` so Cue
    /// (which has full MusicKit access) can do the lookup itself.
    /// Stations route via `resolveURL` even when content is resolved, so the
    /// main app sees the original `/station/<slug>/<id>` URL and can derive
    /// a title (the `cue://` form drops the slug).
    private var openInCueURL: URL? {
        if let content, !content.content.type.isRadio { return content.shareURL }
        return resolveURL
    }

    private var viewInCueURL: URL? {
        if let content, !content.content.type.isRadio { return content.viewURL }
        return resolveURL
    }

    private var resolveURL: URL? {
        guard let url = viewModel.url else { return nil }
        var components = URLComponents(string: "cue://resolve")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url
    }

    private var queueContent: some View {
        VStack(spacing: 0) {
            if #available(iOS 26.0, *) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if self.content != nil {
                            destinationList
                        }
                    }
                    .disabled(isQueueing)
                    .fontDesign(.rounded)
                    .animation(.default, value: sonosService.sorted)
                    .animation(.default, value: destination)
                    .animation(.default, value: groupVolume)
                }
                .safeAreaBar(edge: .top) {
                    if let content { contentHeader(content) }
                }
            } else {
                if let content {
                    contentHeader(content)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if self.content != nil {
                            destinationList
                        }
                    }
                    .disabled(isQueueing)
                    .fontDesign(.rounded)
                    .animation(.default, value: sonosService.sorted)
                    .animation(.default, value: destination)
                    .animation(.default, value: groupVolume)
                }
            }
        }
        .foregroundStyle(.primary)
        .scrollContentBackground(.hidden)
        .overlay { loadingOverlay }
        .overlay { emptyStateOverlay }
        .overlay(alignment: .bottom) { bottomBar }
        .task {
            try? await sonosService.updateGroups()
            try? await sonosService.load(useCache: true)
            impactFeedbackGenerator.prepare()
            restoreDestination()
        }
        .task(id: viewModel.url) {
            guard let url = viewModel.url else { return }
            viewModel.isLoading = true
            defer { viewModel.isLoading = false }

            let fetch = Task { await fetchContent(from: url) }
            let deadline = Task {
                try? await Task.sleep(for: .seconds(3))
                fetch.cancel()
            }
            content = await fetch.value
            deadline.cancel()
            if let type = content?.content.type {
                queuePosition = type.isPlaylist ? .replace : .now
            }
            fallBackFromDeviceIfNeeded()
        }
    }

    // MARK: - Sections

    private func contentHeader(_ content: PlayableContent) -> some View {
        VStack {
            Button {
                dismiss(opening: viewInCueURL)
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    VibeContentArtworkView(content: content)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .environment(sonosService)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title).font(.headline).lineLimit(2)
                        Text(content.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("View in Cue")
                }
                .padding(8)
                .background {
                    if #available(iOS 26.0, *) {
                        Color.clear
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial)
                    }
                }
                .glassEffectIfAvailable(cornerRadius: 12)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            if !content.content.type.isRadio {
                Picker("Play", selection: $queuePosition) {
                    ForEach([QueuePosition.now, .next, .end, .replace]) { position in
                        Text(position.shortTitle).tag(position)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// The one thing this sheet asks for: where to play. The phone first, then
    /// every Sonos group. Picking a row only selects it — `performPlay` commits,
    /// so the position picker and volume above still apply to the choice.
    @ViewBuilder
    private var destinationList: some View {
        deviceRow
        ForEach(groups) { groupRow($0) }
    }

    private var deviceRow: some View {
        destinationButton(
            destination: .device,
            title: "This Device",
            subtitle: canPlayOnDevice ? "Play on this \(deviceNoun)" : "Not available for this link",
            trailingText: nil,
            enabled: canPlayOnDevice,
            isPlaying: false
        )
    }

    private func groupRow(_ group: GroupRoom) -> some View {
        let trackName = group.coordinatorRoom.track.name
        return destinationButton(
            destination: .group(group.coordinatorID),
            title: group.nameWithCount,
            subtitle: trackName.isEmpty ? "—" : trackName,
            trailingText: "\(Int(group.groupVolume))",
            enabled: true,
            isPlaying: group.coordinatorRoom.isPlaying
        )
    }

    private func destinationButton(
        destination target: PlayDestination,
        title: String,
        subtitle: String,
        trailingText: String?,
        enabled: Bool,
        isPlaying: Bool
    ) -> some View {
        let isSelected = destination == target

        return Button {
            impactFeedbackGenerator.impactOccurred()
            select(target)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1, reservesSpace: true)
                        .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                }
                Spacer(minLength: 4)
                if let trailingText {
                    Text(trailingText)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                }
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2)
                        .opacity(isSelected ? 0 : 1)
                    Circle()
                        .fill(.teal.gradient)
                        .opacity(isSelected ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(width: 26, height: 26)
                .animation(.snappy, value: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .padding(.horizontal)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var deviceNoun: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 16) {
            VStack {
                // Only a Sonos group has a volume this sheet can set — the
                // phone's is the system volume, which isn't ours to move.
                if selectedGroup != nil {
                    Button {
                        withAnimation(.interactiveSpring) {
                            setVolume.toggle()
                        }
                    } label: {
                        Label("Volume", systemImage: "speaker.wave.2.fill")
                            .font(.caption.smallCaps())
                    }
                    .geometryGroup()
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.primary.opacity(0.8))
                    .colorScheme(.light)
                }

                playButtons
                    .tint(.accentColor)
            }
            if setVolume, selectedGroup != nil {
                volumeRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)).animation(.interactiveSpring))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            volumeButton(symbol: "minus") { groupVolume = max(0, groupVolume - 1) }
            VibeSlider(value: $groupVolume, step: 1, showValue: true)
            volumeButton(symbol: "plus") { groupVolume = min(100, groupVolume + 1) }
        }
        .frame(height: 28)
    }

    private func volumeButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .bold()
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .buttonRepeatBehavior(.enabled)
    }

    @ViewBuilder
    private var playButtons: some View {
        if isArtist {
            HStack(spacing: 8) {
                Button { performPlay(asArtistRadio: true) } label: {
                    Label("Play Radio", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity).bold().fontDesign(.rounded)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canPlay || isQueueing)

                Button { dismiss(opening: content?.viewURL) } label: {
                    Label("Show", systemImage: "info.circle")
                        .frame(maxWidth: .infinity).bold().fontDesign(.rounded)
                }
                .buttonStyle(.bordered)
                .disabled(isQueueing)
            }
        } else {
            let isRadio = content?.content.type.isRadio ?? false
            Button {
                performPlay()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text(isRadio ? "Play" : queuePosition.title)
                        .contentTransition(.identity)
                }
                .frame(maxWidth: .infinity)
                .bold()
                .fontDesign(.rounded)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPlay || isQueueing)
            .opacity((!canPlay || isQueueing) ? 0.4 : 1)
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var loadingOverlay: some View {
        if isQueueing {
            ProgressView()
                .background {
                    Circle().padding().foregroundStyle(.thinMaterial)
                }
        }
    }

    @ViewBuilder
    private var emptyStateOverlay: some View {
        if content == nil, !viewModel.isLoading {
            VStack(spacing: 10) {
                if let service = detectedService {
                    service.icon
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                }
                Text(viewModel.url == nil ? "No music link found" : "Couldn't load info").font(.title3.bold())
                Text(viewModel.url == nil
                     ? "Share a song, album, or playlist from Apple Music, Spotify, or Tidal."
                     : "Open in Cue to look it up there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    dismiss(opening: openInCueURL)
                } label: {
                    Text("Open in Cue")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.url == nil)
            }
        }
        if content != nil, sonosService.groups.isEmpty, !canPlayOnDevice {
            Text("No system available").font(.title).padding()
        }
        if viewModel.isLoading {
            loadingIndicator
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        VStack(spacing: 14) {
            if let service = detectedService {
                service.icon
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            ProgressView()
        }
    }

    private var detectedService: MusicService? {
        guard let host = viewModel.url?.host?.lowercased() else { return nil }
        if host.contains("apple") { return .apple }
        if host.contains("spotify") { return .spotify }
        if host.contains("tidal") { return .tidal }
        if host.contains("tunein") { return .tuneIn }
        if host.contains("plex") { return .plex }
        if host.contains("soundcloud") { return .soundcloud }
        if host.contains("deezer") || host.hasSuffix("dzr.page.link") { return .deezer }
        return nil
    }

    // MARK: - Actions

    private func dismiss() {
        context?.completeRequest(returningItems: [])
    }

    private func dismiss(opening url: URL?) {
        let target = url ?? URL(string: "cue://")!
        openURL?(target)
        dismiss()
    }

    private func select(_ target: PlayDestination) {
        destination = target
        if let group = groups.first(where: { $0.coordinatorID == target.groupID }), groupVolume.isZero {
            groupVolume = group.groupVolume
        }
    }

    /// Restores the destination from the last share. A remembered group that
    /// has since been regrouped away (its coordinator is now a member of some
    /// other group) or powered off would leave Play pointing at nothing, so
    /// that falls back to the phone rather than silently doing nothing.
    private func restoreDestination() {
        guard !didRestoreDestination else { return }
        didRestoreDestination = true
        guard let remembered = PlayDestination.remembered else { return }
        switch remembered {
        case .device:
            destination = .device
        case let .group(id):
            guard groups.contains(where: { $0.coordinatorID == id }) else { return }
            select(.group(id))
        }
        // Groups and content resolve in two independent tasks, so whichever
        // lands second has to re-run the check.
        fallBackFromDeviceIfNeeded()
    }

    /// A Spotify or Tidal link has no local backend, so a remembered Device
    /// choice would leave Play greyed out with nothing to press. Move to a
    /// group instead — without remembering it, since the user didn't pick it.
    private func fallBackFromDeviceIfNeeded() {
        guard destination == .device, content != nil, !canPlayOnDevice else { return }
        guard let group = groups.first(where: { $0.coordinatorRoom.isPlaying }) ?? groups.first else { return }
        destination = .group(group.coordinatorID)
    }

    /// The phone can't play from in here — `ApplicationMusicPlayer` doesn't run
    /// in an app extension, and this process ends the moment the sheet closes —
    /// so Device hands the content to the main app, which owns
    /// `LocalPlaybackService`. `device=1` is what tells it to play rather than
    /// open the room picker; it falls back to that picker on its own when the
    /// local queue turns out not to take the content.
    private var deviceHandoffURL: URL? {
        guard let base = openInCueURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "device", value: "1"),
            URLQueryItem(name: "position", value: queuePosition.linkValue)
        ]
        return components.url
    }

    private func performPlay(asArtistRadio: Bool = false) {
        guard let baseContent = content else { return }
        let contentToPlay = asArtistRadio ? baseContent.asArtistRadio() : baseContent
        destination.remember()

        switch destination {
        case .device:
            impactFeedbackGenerator.impactOccurred()
            dismiss(opening: deviceHandoffURL)
        case .group:
            guard let group = selectedGroup else { return }
            playInGroup(group, content: contentToPlay)
        }
    }

    private func playInGroup(_ group: GroupRoom, content contentToPlay: PlayableContent) {
        isQueueing = true
        Task {
            defer { isQueueing = false }
            impactFeedbackGenerator.impactOccurred()
            playHistoryService.history.remove(contentToPlay)
            playHistoryService.history.insert(contentToPlay, at: 0)

            try await sonosService.queue(playable: contentToPlay, group: group, position: queuePosition)
            await sonosService.play(ip: group.ip)

            if setVolume {
                await sonosService.setGroupVolume(ip: group.ip, volume: Int(groupVolume))
                await withTaskGroup(of: Void.self) { tasks in
                    for room in group.rooms {
                        tasks.addTask { await sonosService.setRoomMute(IP: room.ip, mute: false) }
                    }
                }
            }

            try await Task.sleep(for: .microseconds(200))
            await sonosService.snapShotGroup(ip: group.ip)

            dismiss(opening: URL(string: "cue://device?id=\(group.coordinatorID)"))
        }
    }

    // MARK: - Lookup

    private static let lookupTimeout: TimeInterval = 5

    private static let lookupSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = lookupTimeout
        config.timeoutIntervalForResource = lookupTimeout
        return URLSession(configuration: config)
    }()

    private static let appleMusicAPI = AppleMusicSearchAPI(session: lookupSession)
    private static let spotifyOpenGraph = SpotifyOpenGraphAPI(session: lookupSession, timeout: lookupTimeout)

    private func fetchContent(from url: URL?) async -> PlayableContent? {
        guard let url else { return nil }
        if url.host?.contains("music.apple.com") == true,
           let result = await lookupAppleMusic(url: url) {
            return result
        }
        if url.host?.contains("spotify") == true,
           let result = await lookupSpotify(url: url) {
            return result
        }
        // Fallback: SonosService (Tidal, Plex, TuneIn, SoundCloud, library, etc.)
        return await sonosService.getContent(from: url)
    }

    private func lookupAppleMusic(url: URL) async -> PlayableContent? {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let trackQueryID = queryItems.first(where: { $0.name == "i" })?.value
        let pathParts = url.pathComponents.filter { $0 != "/" }

        let lookupID: String
        let contentType: ContentType
        if let trackQueryID {
            lookupID = trackQueryID
            contentType = .track
        } else if pathParts.count >= 3, let pathID = pathParts.last {
            // Handles both `/<storefront>/<type>/<slug>/<id>` and slug-less
            // `/<storefront>/<type>/<id>` Apple Music URL forms.
            lookupID = pathID
            switch pathParts[1] {
            case "album": contentType = .album
            case "song": contentType = .track
            case "playlist": contentType = .playlist
            case "artist": contentType = .artist
            case "station": contentType = .radio
            default: return nil
            }
        } else {
            return nil
        }

        let preferredWrapper: String
        switch contentType {
        case .artist: preferredWrapper = "artist"
        case .album, .playlist: preferredWrapper = "collection"
        default: preferredWrapper = "track"
        }

        let media = MediaContent(service: .apple, id: lookupID, type: contentType, location: url)

        if let item = await Self.appleMusicAPI.lookup(id: lookupID, preferredWrapperType: preferredWrapper) {
            return PlayableContent(
                title: item.displayTitle,
                subtitle: item.displaySubtitle,
                thumbnail: item.artworkURL(size: 100),
                artwork: item.artworkURL(size: 600),
                content: media
            )
        }

        // Fallback: scrape music.apple.com for og:* tags. Covers editorial playlists
        // (`pl.u-...` IDs) and other content the iTunes Lookup API doesn't surface.
        let og = await AppleMusicOpenGraphAPI.lookup(url: url, session: Self.lookupSession, timeout: Self.lookupTimeout)

        // Personalized stations (`ra.u-*`) often have no scrapeable og:* tags,
        // so we fall back to a slug-derived name and skip the og-required guard.
        let isStation = contentType == .radio
        // Station URLs are `/<storefront>/station/<slug>/<id>`; slug is at [2].
        // Slug-less `/<storefront>/station/<id>` (3 parts) has no name to derive.
        let slugTitle: String? = {
            guard isStation, pathParts.count >= 4 else { return nil }
            let slug = pathParts[2].replacingOccurrences(of: "-", with: " ")
            return slug.isEmpty ? nil : slug.capitalized
        }()

        guard og.title != nil || og.image != nil || slugTitle != nil else { return nil }

        let subtitle: String
        switch contentType {
        case .artist: subtitle = "Artist"
        case .radio: subtitle = "Station"
        default: subtitle = og.resolvedAuthor ?? ""
        }

        return PlayableContent(
            title: og.resolvedTitle ?? og.title ?? slugTitle ?? "",
            subtitle: subtitle,
            thumbnail: og.image,
            artwork: og.image,
            content: media
        )
    }

    private func lookupSpotify(url: URL) async -> PlayableContent? {
        let normalized = normalizeSpotifyURL(url) ?? url
        let pathParts = normalized.pathComponents.filter { $0 != "/" }
        guard pathParts.count >= 2,
              let contentType = spotifyContentType(for: pathParts[0]) else {
            return nil
        }
        let id = pathParts[1]
        let og = await Self.spotifyOpenGraph.lookup(url: normalized)
      
        return PlayableContent(
            title: og.title ?? "",
            subtitle: og.description?.capitalized ?? "",
            thumbnail: og.image,
            artwork: og.image,
            content: MediaContent(service: .spotify, id: id, type: contentType, location: normalized)
        )
    }

    private func normalizeSpotifyURL(_ url: URL) -> URL? {
        guard url.scheme == "spotify" else { return nil }
        let parts = url.absoluteString
            .replacingOccurrences(of: "spotify:", with: "")
            .split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[0])/\(parts[1])")
    }

    private func spotifyContentType(for path: String) -> ContentType? {
        switch path {
        case "track": return .track
        case "album": return .album
        case "playlist": return .playlist
        case "artist": return .artist
        default: return nil
        }
    }

    // MARK: - View model

    @Observable
    final class ViewModel {
        var url: URL?
        var isLoading: Bool = true
    }
}

// MARK: - View helpers

private extension View {
    @ViewBuilder
    func glassEffectIfAvailable(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
        }
    }
}

// MARK: - PlayableContent helpers

private extension PlayableContent {
    func asArtistRadio() -> PlayableContent {
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


#Preview {
    @Previewable var viewModel = QueueListView.ViewModel()
    
    QueueListView(viewModel: viewModel, context: nil) { url in
        print(url)
    }
    .task {
        try? await SonosService.shared.load(useCache: true)
        viewModel.url = URL(string: "https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb")
    }
}


#Preview("Radio") {
    @Previewable var viewModel = QueueListView.ViewModel()
    
    QueueListView(viewModel: viewModel, context: nil) { url in
        print(url)
    }
    .task {
        try? await SonosService.shared.load(useCache: true)
        viewModel.url = URL(string: "https://music.apple.com/us/station/elton-john-similar-artists-station/ra.54657")
    }
}



#Preview("Song") {
    @Previewable var viewModel = QueueListView.ViewModel()
    
    QueueListView(viewModel: viewModel, context: nil) { url in
        print(url)
    }
    .task {
        try? await SonosService.shared.load(useCache: true)
        viewModel.url = URL(string: "https://open.spotify.com/track/25jgQBxuUkGDdCG1WGKKN9?si=11d390b443bc42db")
    }
}

#Preview("Album") {
    @Previewable var viewModel = QueueListView.ViewModel()
    
    QueueListView(viewModel: viewModel, context: nil) { url in
        print(url)
    }
    .task {
        try? await SonosService.shared.load(useCache: true)
        viewModel.url = URL(string: "https://open.spotify.com/album/6NC5rf0j1JcmXhKNlZqWkr?si=4WM1auarTf65ihxF-7UcJw")
    }
}



#Preview("Album") {
    @Previewable var viewModel = QueueListView.ViewModel()
    
    QueueListView(viewModel: viewModel, context: nil) { url in
        print(url)
    }
    .task {
        try? await SonosService.shared.load(useCache: true)
        viewModel.url = URL(string: "https://open.spotify.com/album/6NC5rf0j1JcmXhKNlZqWkr?si=4WM1auarTf65ihxF-7UcJw")
    }
}
