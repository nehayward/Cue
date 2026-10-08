import Defaults
import SonosKit
import SwiftUI

/// Adds a Plex album (or artist) to one of the library's collections, or
/// starts a new collection with it (the + button). Only the hand-made
/// collections that hold its kind of item are offered: a smart collection is
/// a saved filter, with nothing to add to. The last few added to sit at the
/// top, and the banner that confirms an add opens the collection.
struct AddToPlexCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AlertService.self) private var alertService
    @Environment(PlexBrowseService.self) private var plexBrowseService

    let content: PlayableContent

    /// Nil while loading.
    @State private var collections: [PlayableContent]?
    @State private var loadFailed = false
    @State private var isOwner = true
    @State private var query = ""
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    /// A change is on its way; the list takes no more taps meanwhile.
    @State private var isSaving = false
    @State private var recentIDs: [String] = []

    /// The collections to show, split into the last few added to (hidden
    /// while searching) and the rest.
    private var sections: (recent: [PlayableContent], other: [PlayableContent]) {
        let all = collections ?? []
        guard query.isEmpty else {
            return ([], all.filter { $0.title.localizedCaseInsensitiveContains(query) })
        }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = Array(recentIDs.compactMap { byID[$0] }.prefix(3))
        let recentSet = Set(recent.map(\.id))
        return (recent, all.filter { !recentSet.contains($0.id) })
    }

    var body: some View {
        NavigationStack {
            List {
                if isOwner {
                    collectionRows
                } else {
                    ContentUnavailableView(
                        "Only the Owner Can Edit Collections",
                        systemImage: "lock",
                        description: Text("Collections belong to the Plex server's library, which only its owner can change.")
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .disabled(isSaving)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                if isSaving {
                    ToolbarItem(placement: .confirmationAction) {
                        ProgressView()
                    }
                } else if isOwner {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            newCollectionName = ""
                            showNewCollectionAlert = true
                        } label: {
                            Label("New Collection", systemImage: "plus")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Find collection")
            .alert("New Collection", isPresented: $showNewCollectionAlert) {
                TextField("Collection name", text: $newCollectionName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createCollection() }
            } message: {
                Text("Make a collection with “\(content.title)”.")
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            recentIDs = RecentPlexCollections.ids
            isOwner = await plexBrowseService.checkCollectionAccess()
            guard isOwner else { return }
            collections = await plexBrowseService.collections(accepting: content)
            loadFailed = collections == nil
        }
    }

    @ViewBuilder
    private var collectionRows: some View {
        if let collections {
            let sections = self.sections
            if sections.recent.isEmpty, sections.other.isEmpty {
                Group {
                    if collections.isEmpty {
                        ContentUnavailableView(
                            "No Collections",
                            systemImage: "square.stack.3d.up",
                            description: Text("Start one with the + button.")
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .listRowSeparator(.hidden)
            } else {
                if !sections.recent.isEmpty {
                    Section("Recently Added") {
                        ForEach(sections.recent) { collectionButton($0) }
                    }
                    .listSectionSeparator(.hidden)
                }
                Section {
                    ForEach(sections.other) { collectionButton($0) }
                } header: {
                    if !sections.recent.isEmpty {
                        Text("All Collections")
                    }
                }
                .listSectionSeparator(.hidden)
            }
        } else if loadFailed {
            ContentUnavailableView(
                "Couldn't Load Collections",
                systemImage: "wifi.exclamationmark",
                description: Text("Check that your Plex server is reachable.")
            )
            .listRowSeparator(.hidden)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
        }
    }

    private func collectionButton(_ collection: PlayableContent) -> some View {
        Button {
            add(to: collection)
        } label: {
            row(for: collection)
        }
        .tint(.primary)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private func row(for collection: PlayableContent) -> some View {
        HStack(spacing: 12) {
            ContentArtworkView(content: collection, showMusicSource: false)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .lineLimit(1)
                if !collection.subtitle.isEmpty {
                    Text(collection.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }

    private func add(to collection: PlayableContent) {
        isSaving = true
        Task {
            if await plexBrowseService.add(content, to: collection) {
                RecentPlexCollections.record(collection)
                alertService.showAlertContent(with: content, subtitle: "Added to \(collection.title)", symbolName: "plus")
                // After showAlertContent, which clears any earlier tap.
                deepLink(to: collection)
                dismiss()
            } else {
                alertService.showAlert(with: "Couldn’t add to \(collection.title)", imageName: "exclamationmark.triangle")
                isSaving = false
            }
        }
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSaving = true
        Task {
            if let created = await plexBrowseService.createCollection(named: name, with: content) {
                RecentPlexCollections.record(created)
                alertService.showAlertContent(with: content, subtitle: "Created \(name)", symbolName: "plus")
                deepLink(to: created)
                dismiss()
            } else {
                alertService.showAlert(with: "Couldn’t create \(name)", imageName: "exclamationmark.triangle")
                isSaving = false
            }
        }
    }

    /// Makes the banner tap through to the collection.
    private func deepLink(to collection: PlayableContent) {
        alertService.alert.handleTap = {
            Router.main.presentedSheet = .mediaDetail(content: collection, group: nil)
        }
    }
}

/// The Plex collections most recently added to, most recent first, for the
/// sheet's Recently Added section.
private enum RecentPlexCollections {
    private static let limit = 12

    static var ids: [String] {
        UserDefaults.standard.stringArray(forKey: AppStorageKeys.recentPlexCollectionIDs) ?? []
    }

    static func record(_ collection: PlayableContent) {
        var recents = ids.filter { $0 != collection.id }
        recents.insert(collection.id, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(limit)), forKey: AppStorageKeys.recentPlexCollectionIDs)
    }
}
