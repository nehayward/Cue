import NukeUI
import SonosKit
import SwiftUI

/// The on-device library's Albums or Artists page: what's here, grouped,
/// with a local search and sort. A row opens the songs of that album or
/// artist that are on the device — no server is asked — with a Play All
/// that queues just those. Narrowed to one provider's songs from its
/// Downloaded page; everything for Offline Mode.
struct OnDeviceCollectionScreen: View {
    let collection: OnDeviceCollection
    var service: MusicService? = nil

    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared
    @State private var searchText = ""
    @State private var sort: OnDeviceLibrary.GroupSort = .title
    @State private var isDescending = false

    var body: some View {
        // Read here so a download finishing or an index rebuilding re-runs
        // the grouping; the library itself is static.
        _ = downloads.completed.count
        _ = apple.version
        _ = files.indexVersion
        let groups = OnDeviceLibrary.groups(collection, matching: searchText, sortedBy: sort, descending: isDescending, in: service)
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty

        return List {
            ForEach(groups) { group in
                NavigationLink(value: OnDeviceLibrary.destination(for: group)) {
                    OnDeviceGroupRow(group: group, collection: collection)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if groups.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("Nothing on This Device", systemImage: "arrow.down.circle")
                    } description: {
                        Text(OnDeviceLibrary.emptyDescription(for: service))
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search \(collection.title)")
        .onAppear {
            apple.refreshIfNeeded()
        }
        .miniPlayerOnScrollHandler()
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !groups.isEmpty || isSearching {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(collection.title)
                            .font(.headline)
                        Text(groups.count == 1
                             ? (collection == .albums ? "1 album" : "1 artist")
                             : "\(groups.count.formatted()) \(collection.title.lowercased())")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: $sort) {
                            ForEach(OnDeviceLibrary.GroupSort.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                        Picker("Order", selection: $isDescending) {
                            Text(sort == .added ? "Oldest First" : "A – Z").tag(false)
                            Text(sort == .added ? "Newest First" : "Z – A").tag(true)
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .onChange(of: sort) { _, newValue in
            // Each order starts in its own natural direction.
            isDescending = newValue == .added
        }
    }
}

/// One album or artist on the device: art, name, the line under it, and
/// for an album its song count. Shared by the grouped pages and the Search
/// tab's offline results.
struct OnDeviceGroupRow: View {
    let group: OnDeviceLibrary.Group
    let collection: OnDeviceCollection

    var body: some View {
        HStack(spacing: 12) {
            LazyImage(url: group.artwork) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay {
                            Image(systemName: collection.systemImage)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(collection == .artists ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .lineLimit(1)
                Text(group.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if collection == .albums {
                Text(group.trackCount == 1 ? "1 song" : "\(group.trackCount) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    NavigationStack {
        OnDeviceCollectionScreen(collection: .albums)
    }
    .withEnvironments()
}
