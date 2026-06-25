import SwiftUI
import SonosKit
import MusicSearchKit
import VibesDS
import OSLog

struct QueueListView: View {
    private let sonosService: SonosService = .shared
    private let playHistoryService = PlayHistoryService.shared
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()

    @State private var content: PlayableContent?
    @State private var rooms: [Room] = []
    @State private var selections = Set<String>()
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

    private func liveGroup(for roomID: String) -> GroupRoom? {
        guard let group = sonosService.groups.first(where: { $0.rooms.contains { $0.id == roomID } }),
              group.rooms.count > 1 else { return nil }
        return group
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
    /// Stations route via `resolveURL` even when content is resolved, so the
    /// main app sees the original `/station/<slug>/<id>` URL and can derive
    /// a title (the `clic://` form drops the slug).
    private var openInClicURL: URL? {
        if let content, !content.content.type.isRadio { return content.shareURL }
        return resolveURL
    }

    private var viewInClicURL: URL? {
        if let content, !content.content.type.isRadio { return content.viewURL }
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
            if #available(iOS 26.0, *) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if self.content != nil {
                            multiRoomGroupsScroll
                            Divider()
                                .padding(.horizontal)
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
                            multiRoomGroupsScroll
                            Divider()
                                .padding(.horizontal)
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
            if let type = content?.content.type {
                queuePosition = type.isPlaylist ? .replace : .now
            }
        }
    }

    // MARK: - Sections

    private func contentHeader(_ content: PlayableContent) -> some View {
        VStack {
            Button {
                dismiss(opening: viewInClicURL)
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
            VStack(alignment: .leading) {
                HStack(spacing: 12) {
                    Text(group.nameWithCount).fontWeight(.semibold).lineLimit(1)
                    Spacer()
                    Text("\(Int(group.groupVolume))").font(.callout).foregroundStyle(.secondary)
                }
                Text(group.coordinatorRoom.track.name)
                    .font(.caption)
                    .lineLimit(1, reservesSpace: true)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
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

    @ViewBuilder
    private func roomRow(_ room: Room) -> some View {
        let isSelected = selections.contains(room.id)
        let isPlaying = isRoomPlaying(room.id)
        let group = liveGroup(for: room.id)
        let trackName = currentTrackName(for: room.id)
        let subtitle: String = {
            if !trackName.isEmpty { return trackName }
            guard let g = group else { return "—" }
            let extra = g.rooms.count - 1
            return "Grouped with \(g.coordinatorRoom.name)\(extra > 1 ? " +\(extra - 1)" : "")"
        }()

        Button {
            impactFeedbackGenerator.impactOccurred()
            toggleSelection(room)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name).font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1, reservesSpace: true)
                        .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                }
                Spacer(minLength: 4)
                Text("\(Int(room.volume))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2)
                        .opacity(isSelected ? 0 : 1)
                    Circle()
                        .fill(Color.accentColor)
                        .opacity(isSelected ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
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
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 16) {
            VStack {
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
                
                playButtons
                    .tint(.accent)
            }
            if setVolume {
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
            Button {
                performPlay()
            } label: {
                Text("Play")
                    .frame(maxWidth: .infinity)
                    .bold()
                    .fontDesign(.rounded)
            }
            .buttonStyle(.bordered)
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
        if host.contains("deezer") || host.hasSuffix("dzr.page.link") { return .deezer }
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
        let active = sonosService.sortedRooms.filter { $0.state == .active }
        let snapshots = active.map { source in
            let room = Room(id: source.id, ip: source.ip, name: source.name, channelMap: source.channelMap)
            room.volume = source.volume
            return room
        }
        rooms = snapshots
        // Fetch live volume per room — the extension has no watcher to refresh these.
        await withTaskGroup(of: (String, Double).self) { group in
            for room in snapshots {
                group.addTask {
                    let volume = (try? await sonosService.getVolume(ip: room.ip)) ?? room.volume
                    return (room.id, volume)
                }
            }
            for await (id, volume) in group {
                if let room = snapshots.first(where: { $0.id == id }) {
                    room.volume = volume
                }
            }
        }
    }

    private func playInGroup(_ group: GroupRoom) {
        guard let content else { return }
        isQueueing = true
        Task {
            defer { isQueueing = false }
            impactFeedbackGenerator.impactOccurred()
            playHistoryService.history.remove(content)
            playHistoryService.history.insert(content, at: 0)

            try await sonosService.queue(playable: content, group: group, position: queuePosition)
            await sonosService.play(ip: group.ip)

            dismiss(opening: URL(string: "clic://device?id=\(group.coordinatorID)"))
        }
    }

    private func performPlay(asArtistRadio: Bool = false) {
        guard let baseContent = content else { return }
        let contentToPlay = asArtistRadio ? baseContent.asArtistRadio() : baseContent
        isQueueing = true

        Task {
            defer { isQueueing = false }
            impactFeedbackGenerator.impactOccurred()
            let selectedRooms = rooms.filter { selections.contains($0.id) }
            guard let newGroup = await sonosService.speedGroup(rooms: selectedRooms) else { return }

            playHistoryService.history.remove(contentToPlay)
            playHistoryService.history.insert(contentToPlay, at: 0)

            try await sonosService.queue(playable: contentToPlay, group: newGroup, position: queuePosition)
            await sonosService.play(ip: newGroup.ip)

            if setVolume {
                await withTaskGroup(of: Void.self) { group in
                    for room in selectedRooms {
                        group.addTask {
                            await sonosService.setDeviceVolume(ip: room.ip, volume: Int(groupVolume))
                            await sonosService.setRoomMute(IP: room.ip, mute: false)
                        }
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
