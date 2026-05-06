import SwiftUI
import SonosKit
import MusicSearchKit
import VibesDS
import OSLog

private let log = Logger(subsystem: "com.nick.Clic.QueueAction", category: "queue")

struct QueueListView: View {
    private let sonosService: SonosService = .shared
    private let playHistoryService = PlayHistoryService.shared
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()

    @State private var content: PlayableContent?
    @State private var rooms: [Room] = []
    @State private var selections = Set<String>()
    @State private var groupVolume: Double = 0
    @State private var isQueueing = false

    var viewModel: ViewModel
    var context: NSExtensionContext?
    var openURL: ((URL) -> Void)?

    init(viewModel: ViewModel, context: NSExtensionContext? = nil, openURL: ((URL) -> Void)?) {
        self.viewModel = viewModel
        self.context = context
        self.openURL = openURL
    }

    // MARK: - Derived state

    private var allSelected: Bool {
        !rooms.isEmpty && selections.count == rooms.count
    }

    private var isArtist: Bool {
        content?.content.type == .artist
    }

    private var multiRoomGroups: [GroupRoom] {
        sonosService.groups.filter { $0.rooms.count > 1 }
    }

    private var sortedRooms: [Room] {
        rooms.sorted { isRoomPlaying($0.id) && !isRoomPlaying($1.id) }
    }

    private func isRoomPlaying(_ id: String) -> Bool {
        sonosService.sortedRooms.first { $0.id == id }?.isPlaying ?? false
    }

    private func currentTrackName(for id: String) -> String {
        sonosService.sortedRooms.first { $0.id == id }?.track.name ?? ""
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
        .tint(.teal)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.callout.weight(.semibold))
            }
            .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { dismiss(opening: openInClicURL) } label: {
                    Label("Open in Clic", systemImage: "play.circle")
                }
                .disabled(viewModel.url == nil)

                Button { dismiss(opening: viewInClicURL) } label: {
                    Label("View in Clic", systemImage: "info.circle")
                }
                .disabled(viewModel.url == nil)
            } label: {
                Image(systemName: "ellipsis").font(.callout.weight(.semibold))
            }
        }
    }

    /// Prefers the resolved content's `clic://play/...` URL when we have it; otherwise
    /// hands the raw shared URL to the main app via `clic://resolve?url=...` so Clic
    /// (which has full MusicKit access) can do the lookup itself.
    private var openInClicURL: URL? {
        if let content { return content.shareURL }
        return resolveURL
    }

    private var viewInClicURL: URL? {
        if let content { return content.viewURL }
        return resolveURL
    }

    private var resolveURL: URL? {
        guard let url = viewModel.url else { return nil }
        var components = URLComponents(string: "clic://resolve")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url
    }

    private var queueContent: some View {
        VStack(spacing: 0) {
            if let content { contentHeader(content) }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if self.content != nil {
                        multiRoomGroupsScroll
                        everywhereButton
                        ForEach(sortedRooms) { roomRow($0) }
                    }
                }
                .disabled(isQueueing)
                .fontDesign(.rounded)
                .onAppear { Task { await refreshRooms() } }
                .animation(.default, value: sonosService.sorted)
                .animation(.default, value: selections)
                .animation(.default, value: groupVolume)
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
        }
    }

    // MARK: - Sections

    private func contentHeader(_ content: PlayableContent) -> some View {
        Button {
            dismiss(opening: content.viewURL)
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
                    .accessibilityLabel("View in Clic")
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thinMaterial)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var multiRoomGroupsScroll: some View {
        if !multiRoomGroups.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(multiRoomGroups) { groupCard($0) }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func groupCard(_ group: GroupRoom) -> some View {
        Button {
            playInGroup(group)
        } label: {
            HStack(spacing: 12) {
                Text(group.nameWithCount).fontWeight(.semibold).lineLimit(1)
                Spacer()
                Text("\(Int(group.groupVolume))").font(.callout).foregroundStyle(.secondary)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12).foregroundStyle(.thinMaterial)
            }
            .containerRelativeFrame(.horizontal, alignment: .topLeading) { length, _ in length / 1.75 }
        }
        .buttonStyle(.plain)
    }

    private var everywhereButton: some View {
        Button {
            impactFeedbackGenerator.impactOccurred()
            toggleEverywhere()
        } label: {
            Text(allSelected ? "Deselect All" : "Everywhere")
                .contentTransition(.identity)
                .frame(maxWidth: .infinity)
                .bold()
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    private func roomRow(_ room: Room) -> some View {
        let isSelected = selections.contains(room.id)
        let trackName = currentTrackName(for: room.id)
        let isPlaying = isRoomPlaying(room.id)

        return Button {
            impactFeedbackGenerator.impactOccurred()
            toggleSelection(room)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name).fontWeight(.semibold)
                    if !trackName.isEmpty {
                        Text(trackName)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                    }
                }
                Spacer()
                Text("\(Int(room.volume))").font(.callout).foregroundStyle(.secondary)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary.opacity(0.7))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .padding(.horizontal)
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if content != nil {
            VStack(spacing: 12) {
                volumeRow
                playButtons
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            volumeButton(symbol: "minus") { groupVolume = max(0, groupVolume - 2) }
            VibeSlider(value: $groupVolume, step: 1, showValue: true)
            volumeButton(symbol: "plus") { groupVolume = min(100, groupVolume + 2) }
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
                .disabled(selections.isEmpty || isQueueing)

                Button { dismiss(opening: content?.viewURL) } label: {
                    Label("Show", systemImage: "info.circle")
                        .frame(maxWidth: .infinity).bold().fontDesign(.rounded)
                }
                .buttonStyle(.bordered)
                .disabled(isQueueing)
            }
        } else {
            Button { performPlay() } label: {
                Text("Play").frame(maxWidth: .infinity).bold().fontDesign(.rounded)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selections.isEmpty || isQueueing)
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
                     : "Open in Clic to look it up there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    dismiss(opening: openInClicURL)
                } label: {
                    Text("Open in Clic")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.url == nil)
            }
        }
        if content != nil, sonosService.groups.isEmpty {
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
        return nil
    }

    // MARK: - Actions

    private func dismiss() {
        context?.completeRequest(returningItems: [])
    }

    private func dismiss(opening url: URL?) {
        let target = url ?? URL(string: "clic://")!
        openURL?(target)
        dismiss()
    }

    private func toggleSelection(_ room: Room) {
        if selections.contains(room.id) {
            selections.remove(room.id)
        } else {
            selections.insert(room.id)
            if groupVolume.isZero { groupVolume = room.volume }
        }
    }

    private func toggleEverywhere() {
        if allSelected {
            selections.removeAll()
            return
        }
        for room in rooms {
            if groupVolume.isZero { groupVolume = room.volume }
            selections.insert(room.id)
        }
    }

    private func refreshRooms() async {
        if sonosService.sortedRooms.isEmpty {
            try? await sonosService.updateGroups()
        }
        rooms = sonosService.sortedRooms
            .filter { $0.state == .active }
            .map { source in
                let room = Room(id: source.id, ip: source.ip, name: source.name, channelMap: source.channelMap)
                room.volume = source.volume
                return room
            }
    }

    private func playInGroup(_ group: GroupRoom) {
        guard let content else { return }
        Task {
            impactFeedbackGenerator.impactOccurred()
            isQueueing = true
            playHistoryService.history.remove(content)
            playHistoryService.history.insert(content, at: 0)

            try await sonosService.queue(playable: content, group: group, position: .now)
            await sonosService.play(ip: group.ip)

            dismiss(opening: URL(string: "clic://device?id=\(group.coordinatorID)"))
        }
    }

    private func performPlay(asArtistRadio: Bool = false) {
        guard let baseContent = content else { return }
        let contentToPlay = asArtistRadio ? baseContent.asArtistRadio() : baseContent

        Task {
            impactFeedbackGenerator.impactOccurred()
            let selectedRooms = rooms.filter { selections.contains($0.id) }
            guard let newGroup = await sonosService.speedGroup(rooms: selectedRooms) else { return }

            isQueueing = true
            playHistoryService.history.remove(contentToPlay)
            playHistoryService.history.insert(contentToPlay, at: 0)

            try await sonosService.queue(playable: contentToPlay, group: newGroup, position: .now)

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await sonosService.play(ip: newGroup.ip) }
                for room in selectedRooms {
                    group.addTask {
                        await sonosService.setDeviceVolume(ip: room.ip, volume: Int(groupVolume))
                        await sonosService.setRoomMute(IP: room.ip, mute: false)
                    }
                }
            }

            try await Task.sleep(for: .microseconds(200))
            await sonosService.snapShotGroup(ip: newGroup.ip)

            dismiss(opening: URL(string: "clic://device?id=\(newGroup.coordinatorID)"))
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
        log.notice("fetchContent: \(url.absoluteString, privacy: .public)")

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
            log.notice("iTunes wrapperType=\(item.wrapperType ?? "nil", privacy: .public) title=\(item.displayTitle, privacy: .public) subtitle=\(item.displaySubtitle, privacy: .public)")
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
        log.notice("iTunes lookup empty for \(lookupID, privacy: .public); falling back to og scrape")
        let og = await AppleMusicOpenGraphAPI.lookup(url: url, session: Self.lookupSession, timeout: Self.lookupTimeout)
        guard og.title != nil || og.image != nil else { return nil }

        let subtitle: String
        switch contentType {
        case .artist: subtitle = "Artist"
        default: subtitle = og.resolvedAuthor ?? ""
        }
        log.notice("AppleMusic og.title=\(og.title ?? "nil", privacy: .public) og.description=\(og.description ?? "nil", privacy: .public) resolvedTitle=\(og.resolvedTitle ?? "nil", privacy: .public) resolvedSubtitle=\(subtitle, privacy: .public)")

        return PlayableContent(
            title: og.resolvedTitle ?? og.title ?? "",
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
            subtitle: og.description ?? "",
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

