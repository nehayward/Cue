import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI
import UniformTypeIdentifiers

/// Brings a playlist into Cue from Spotify or Apple Music — a link, one of
/// the user's Apple Music playlists, or an exported file — and makes it on
/// a service Cue plays, song by song: what's found is added, what's nearly
/// found is added and marked to check, and what isn't can be searched for
/// by hand or left out.
struct ImportPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AlertService.self) private var alertService

    @State private var importer: PlaylistImporter
    @State private var link = ""
    @State private var showsFilePicker = false
    @State private var filter: RowFilter = .all

    enum RowFilter: Hashable {
        case all, toCheck, missing
    }

    init(destination: MusicService? = nil) {
        _importer = State(initialValue: PlaylistImporter(destination: destination))
    }

    var body: some View {
        NavigationStack {
            Group {
                if PlaylistImporter.destinations.isEmpty {
                    noDestination
                } else {
                    switch importer.phase {
                    case .start, .reading:
                        sourceForm
                    case .matching, .review, .creating:
                        review
                    case let .done(playlist):
                        done(playlist)
                    }
                }
            }
            .navigationTitle("Import Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .onDisappear { importer.cancel() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Cancel")
        }
        if importer.phase == .review || importer.phase == .matching {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await importer.create() }
                } label: {
                    Text("Create")
                        .fontWeight(.semibold)
                }
                .disabled(importer.phase != .review || importer.addedCount == 0 || importer.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Source

    private var sourceForm: some View {
        Form {
            Section {
                TextField("Spotify or Apple Music link", text: $link, axis: .vertical)
                    .lineLimit(1...4)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { importer.load(text: link) }
                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        Task { @MainActor in
                            link = text
                            importer.load(text: text)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    Spacer()
                    Button {
                        importer.load(text: link)
                    } label: {
                        Text("Import")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importer.phase == .reading)
                }
            } header: {
                Text("Link")
            } footer: {
                Text("A playlist or album link from Spotify or Apple Music. You can also paste songs, one per line, as “Artist - Title”.")
            }

            if PlaylistImporter.destinations.contains(.apple) {
                Section {
                    NavigationLink {
                        ApplePlaylistPicker { playlist in
                            importer.load(applePlaylist: playlist)
                        }
                    } label: {
                        Label("Your Apple Music Playlists", systemImage: "music.note.list")
                    }
                }
            }

            Section {
                Button {
                    showsFilePicker = true
                } label: {
                    Label("Import a File…", systemImage: "doc.text")
                }
            } footer: {
                Text("A CSV, M3U or text file. Spotify’s share link only lists a playlist’s first \(SpotifyPlaylistReader.embedLimit) songs; to bring a longer one across, export it to CSV (Exportify does this) and import the file.")
            }

            destinationSection

            if let message = importer.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(importer.phase == .reading)
        .overlay {
            if importer.phase == .reading {
                ProgressView("Reading Playlist…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .fileImporter(
            isPresented: $showsFilePicker,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .m3uPlaylist, .plainText, .text]
        ) { result in
            if case let .success(url) = result {
                importer.load(file: url)
            }
        }
    }

    @ViewBuilder
    private var destinationSection: some View {
        @Bindable var model = importer
        let destinations = PlaylistImporter.destinations
        if destinations.count > 1 {
            Section {
                Picker("Add To", selection: $model.destination) {
                    ForEach(destinations, id: \.self) { service in
                        Text(service.title).tag(service)
                    }
                }
            } footer: {
                if importer.phase != .start, importer.phase != .reading {
                    Text("Changing this looks for the songs again.")
                }
            }
        }
    }

    private var noDestination: some View {
        ContentUnavailableView {
            Label("Nowhere to Import To", systemImage: "music.note.list")
        } description: {
            Text("Set up Apple Music, Plex, Subsonic or a Files folder to bring playlists into Cue.")
        }
    }

    // MARK: - Review

    private var review: some View {
        @Bindable var model = importer
        return List {
            Section {
                header
                TextField("Playlist Name", text: $model.name)
                    .font(.headline)
            }

            if let playlist = importer.playlist, playlist.unreadCount > 0 {
                Section {
                    Label {
                        Text("\(playlist.source.title) only shared the first \(playlist.tracks.count) of \(playlist.totalCount ?? playlist.tracks.count) songs. To bring them all, export the playlist to a CSV file (Exportify does this) and import the file instead.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                }
            }

            destinationSection

            Section {
                summary
                if importer.phase == .review, importer.checkCount + importer.missingCount > 0 {
                    Picker("Show", selection: $filter) {
                        Text("All").tag(RowFilter.all)
                        Text("To Check").tag(RowFilter.toCheck)
                        Text("Not Found").tag(RowFilter.missing)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                ForEach(visibleRows) { row in
                    NavigationLink {
                        ImportMatchPicker(importer: importer, rowID: row.id)
                    } label: {
                        ImportRowView(row: row, isLookingUp: importer.phase == .matching && row.state == .pending)
                    }
                    .disabled(importer.phase != .review)
                }
            } footer: {
                if importer.phase == .review, importer.checkCount > 0 {
                    Button("Keep All Songs to Check") {
                        importer.acceptAllToCheck()
                    }
                    .font(.footnote)
                }
            }

            if let message = importer.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .overlay {
            if importer.phase == .creating {
                ProgressView("Creating Playlist…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .disabled(importer.phase == .creating)
    }

    private var visibleRows: [ImportRow] {
        switch filter {
        case .all: importer.rows
        case .toCheck: importer.rows.filter { $0.state == .check }
        case .missing: importer.rows.filter { $0.state == .missing }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            LazyImage(url: importer.playlist?.artwork) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                if let playlist = importer.playlist {
                    Text("\(playlist.tracks.count) songs from \(playlist.source.title)")
                        .font(.subheadline)
                }
                Text("Into \(importer.destination.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        switch importer.phase {
        case .matching:
            VStack(alignment: .leading, spacing: 6) {
                if importer.progress == 0, let read = importer.librarySyncCount {
                    Text("Reading your \(importer.destination.title) library… \(read) songs")
                        .font(.subheadline)
                        .monospacedDigit()
                } else {
                    Text("Finding songs on \(importer.destination.title)…")
                        .font(.subheadline)
                }
                ProgressView(value: Double(importer.progress), total: Double(max(importer.rows.count, 1)))
                Text("\(importer.progress) of \(importer.rows.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .creating:
            Text("Adding \(importer.addedCount) songs to \(importer.destination.title)…")
                .font(.subheadline)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("\(importer.addedCount) of \(importer.rows.count) songs will be added")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    if importer.checkCount > 0 {
                        Label("\(importer.checkCount) to check", systemImage: ImportRowView.symbol(for: .check))
                            .foregroundStyle(.orange)
                    }
                    if importer.missingCount > 0 {
                        Label("\(importer.missingCount) not found", systemImage: ImportRowView.symbol(for: .missing))
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Done

    private func done(_ playlist: PlayableContent) -> some View {
        ContentUnavailableView {
            Label("Playlist Created", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green, .primary)
        } description: {
            VStack(spacing: 8) {
                Text("“\(playlist.title)” is on \(importer.destination.title) with \(importer.progress) songs.")
                if let message = importer.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        } actions: {
            Button {
                dismiss()
                // Once this sheet is gone: the playlist opens in a sheet of
                // its own, and only one can be up at a time.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                }
            } label: {
                Text("Open Playlist")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)

            Button("Import Another") {
                link = ""
                filter = .all
                importer.reset()
            }
        }
        .onAppear {
            alertService.showAlertContent(with: playlist, subtitle: "Imported Playlist", symbolName: "checkmark")
            alertService.alert.handleTap = {
                Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
            }
        }
    }
}

// MARK: - Rows

/// A song from the source and what it was matched to.
struct ImportRowView: View {
    let row: ImportRow
    var isLookingUp = false

    static func symbol(for state: ImportRow.State) -> String {
        switch state {
        case .pending: "circle.dotted"
        case .matched, .chosen: "checkmark.circle.fill"
        case .check: "exclamationmark.circle.fill"
        case .missing: "xmark.circle.fill"
        case .skipped: "minus.circle"
        }
    }

    private var tint: Color {
        switch row.state {
        case .pending, .skipped: .secondary
        case .matched, .chosen: .green
        case .check: .orange
        case .missing: .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isLookingUp {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: Self.symbol(for: row.state))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.track.title)
                    .lineLimit(1)
                if !row.track.artistLine.isEmpty {
                    Text(row.track.artistLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                matchLine
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var matchLine: some View {
        switch row.state {
        case .pending:
            EmptyView()
        case .skipped:
            Text("Left out")
                .foregroundStyle(.secondary)
        case .missing:
            if let closest = row.matches.first?.item {
                Text("Not found · closest: \(closest.title) — \(closest.metadata?.artist ?? closest.subtitle)")
                    .foregroundStyle(.red)
            } else {
                Text("Not found")
                    .foregroundStyle(.red)
            }
        case .matched, .check, .chosen:
            if let choice = row.choice {
                Text("\(Image(systemName: "arrow.turn.down.right")) \(choice.title) — \(choice.metadata?.artist ?? choice.subtitle)")
                    .foregroundStyle(row.state == .check ? Color.orange : Color.secondary)
            }
        }
    }
}

// MARK: - Picking a match

/// Everything that could stand in for one song: what the matcher found, a
/// search of the destination, or leaving it out.
struct ImportMatchPicker: View {
    @Environment(\.dismiss) private var dismiss
    let importer: PlaylistImporter
    let rowID: Int

    @State private var query = ""
    @State private var results: [PlayableContent] = []
    @State private var isSearching = false

    private var row: ImportRow? {
        importer.rows.first { $0.id == rowID }
    }

    var body: some View {
        List {
            if let row {
                Section("From \(importer.playlist?.source.title ?? "the Playlist")") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.track.title)
                            .font(.headline)
                        Text([row.track.artistLine, row.track.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let duration = row.track.duration {
                            Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !row.matches.isEmpty, query.isEmpty {
                    Section("Found on \(importer.destination.title)") {
                        ForEach(Array(row.matches.enumerated()), id: \.offset) { _, match in
                            candidate(match.item, row: row, confidence: match.confidence)
                        }
                    }
                }

                if !query.isEmpty {
                    Section("Search Results") {
                        if isSearching {
                            ProgressView()
                        } else if results.isEmpty {
                            Text("No songs found")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                                candidate(item, row: row, confidence: nil)
                            }
                        }
                    }
                }

                Section {
                    Button("Leave Out of Playlist", role: .destructive) {
                        importer.skip(rowID)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Choose a Song")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search \(importer.destination.title)")
        .task(id: query) {
            guard !query.isEmpty else {
                results = []
                isSearching = false
                return
            }
            isSearching = true
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await importer.search(query)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
        .onAppear {
            if let row, row.matches.isEmpty, query.isEmpty {
                query = SongMatcher.searchTerm(for: row.track)
            }
        }
    }

    private func candidate(_ item: PlayableContent, row: ImportRow, confidence: SongMatcher.Confidence?) -> some View {
        Button {
            importer.choose(item, for: rowID)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                LazyImage(url: item.thumbnail ?? item.artwork) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .lineLimit(1)
                    Text([item.metadata?.artist ?? item.subtitle, item.metadata?.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let duration = item.metadata?.duration, duration > .zero {
                            Text(duration.formatted(.time(pattern: .minuteSecond)))
                                .monospacedDigit()
                        }
                        if let confidence {
                            Text(confidence == .high ? "Same song" : confidence == .medium ? "Likely" : "Possible")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if row.choice == item {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }
}

// MARK: - Apple Music playlists

/// The user's own Apple Music playlists, to import one.
private struct ApplePlaylistPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (PlayableContent) -> Void

    @State private var playlists: [PlayableContent] = []
    @State private var isLoading = true

    var body: some View {
        List(playlists) { playlist in
            Button {
                dismiss()
                onPick(playlist)
            } label: {
                HStack(spacing: 12) {
                    LazyImage(url: playlist.thumbnail ?? playlist.artwork) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 6))
                    Text(playlist.title)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .tint(.primary)
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list")
            }
        }
        .navigationTitle("Apple Music Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            playlists = await MusicSearchService.shared.appleUserPlaylists()
            isLoading = false
        }
    }
}
