import SwiftUI
import Observation

// MARK: - Section Type Definitions

enum AppleLibrarySection: String, Codable, CaseIterable {
    case artists
    case albums
    case songs
    case playlistFolders
    case playlists
    case recentlyPlayed
    case recentlyAdded
    case recommendedAlbums
    case personalStations
}

enum SpotifyLibrarySection: String, Codable, CaseIterable {
    case likedSongs
    case albums
    case playlists
}

/// A reusable system for managing section ordering and visibility with live updates.
///
/// Usage:
/// 1. Define your sections enum:
///    ```
///    enum MyScreenSection: String, Codable, CaseIterable {
///        case sectionOne, sectionTwo, sectionThree
///    }
///    ```
///
/// 2. Create a shared store in SectionConfigurationStores:
///    ```
///    lazy var myScreen = SectionConfigurationStore<MyScreenSection>(
///        key: "myScreenConfig",
///        defaultSections: [
///            (.sectionOne, "Section One", "Subtitle"),
///            (.sectionTwo, "Section Two", nil)
///        ]
///    )
///    ```
///
/// 3. In your view, use the shared store:
///    ```
///    @State private var configStore = SectionConfigurationStores.shared.myScreen
///
///    ForEach(configStore.configuration.visibleSections(), id: \.self) { section in
///        sectionView(for: section)
///    }
///    ```
///
/// 4. Show reorder sheet via Router (automatically updates in real-time):
///    ```
///    Router.main.presentedSheet = .reorderMyScreenSections
///    ```

// MARK: - Section Configuration Model

struct SectionConfiguration<SectionID: Codable & Hashable & CaseIterable & RawRepresentable>: Codable where SectionID.RawValue == String {
    var sections: [SectionItem]
    
    struct SectionItem: Codable, Identifiable {
        let id: String
        var isVisible: Bool
        var order: Int
        let title: String
        let subtitle: String?
        
        init(id: String, isVisible: Bool = true, order: Int = 0, title: String, subtitle: String? = nil) {
            self.id = id
            self.isVisible = isVisible
            self.order = order
            self.title = title
            self.subtitle = subtitle
        }
    }
    
    init(defaultSections: [(section: SectionID, title: String, subtitle: String?)]) {
        self.sections = defaultSections.enumerated().map { index, item in
            SectionItem(id: item.section.rawValue, isVisible: true, order: index, title: item.title, subtitle: item.subtitle)
        }
    }
    
    func isVisible(_ section: SectionID) -> Bool {
        sections.first(where: { $0.id == section.rawValue })?.isVisible ?? true
    }
    
    func orderedSections() -> [SectionID] {
        sections
            .sorted { $0.order < $1.order }
            .compactMap { item -> SectionID? in
                SectionID(rawValue: item.id)
            }
    }
    
    func visibleSections() -> [SectionID] {
        orderedSections().filter { isVisible($0) }
    }
}

// MARK: - Observable Storage

@Observable
final class SectionConfigurationStore<SectionID: Codable & Hashable & CaseIterable & RawRepresentable> where SectionID.RawValue == String {
    private let key: String
    private let defaultSections: [(section: SectionID, title: String, subtitle: String?)]
    
    var configuration: SectionConfiguration<SectionID> {
        didSet {
            save()
        }
    }
    
    init(key: String, defaultSections: [(section: SectionID, title: String, subtitle: String?)]) {
        self.key = key
        self.defaultSections = defaultSections
        
        // Try to load from UserDefaults, otherwise use default
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(SectionConfiguration<SectionID>.self, from: data) {
            self.configuration = decoded
        } else {
            self.configuration = SectionConfiguration(defaultSections: defaultSections)
        }
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}

// MARK: - Shared Stores

@MainActor
final class SectionConfigurationStores {
    static let shared = SectionConfigurationStores()
    
    private init() {}
    
    lazy var appleLibrary = SectionConfigurationStore<AppleLibrarySection>(
        key: "appleLibrarySectionConfig",
        defaultSections: [
            (.artists, "Artists", "Apple Music"),
            (.albums, "Albums", "Apple Music"),
            (.songs, "Songs", "Apple Music"),
            (.playlistFolders, "Playlist Folders", "Apple Music"),
            (.playlists, "Playlists", "Apple Music"),
            (.recentlyPlayed, "Recently Played", "Apple Music"),
            (.recentlyAdded, "Recently Added", "Apple Music"),
            (.recommendedAlbums, "Recommended Albums", "Apple Music"),
            (.personalStations, "Personal Stations", "Apple Music")
        ]
    )
    
    lazy var spotifyLibrary = SectionConfigurationStore<SpotifyLibrarySection>(
        key: "spotifyLibrarySectionConfig",
        defaultSections: [
            (.likedSongs, "Liked Songs", "Spotify"),
            (.albums, "Albums", "Spotify"),
            (.playlists, "Playlists", "Spotify")
        ]
    )
}

// MARK: - Reorder Sections View

struct ReorderSectionsView<SectionID: Codable & Hashable & CaseIterable & RawRepresentable>: View where SectionID.RawValue == String {
    @Binding var configuration: SectionConfiguration<SectionID>
    
    @State private var items: [SectionConfiguration<SectionID>.SectionItem]
    @Environment(\.dismiss) private var dismiss
    
    init(configuration: Binding<SectionConfiguration<SectionID>>) {
        self._configuration = configuration
        self._items = State(initialValue: configuration.wrappedValue.sections.sorted { $0.order < $1.order })
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                toggleVisibility(for: item)
                            }
                        } label: {
                            Image(systemName: item.isVisible ? "checkmark.circle.fill" : "circle")
                                .fontWeight(.semibold)
                                .contentTransition(.symbolEffect(.automatic))
                                .foregroundStyle(.primary)
                        }
                        .tint(.primary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .opacity(item.isVisible ? 1 : 0.5)
                }
                .onMove { from, to in
                    withAnimation(.spring(response: 0.3)) {
                        items.move(fromOffsets: from, toOffset: to)
                        updateOrder()
                    }
                }
                
                Section {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            restoreDefaults()
                        }
                    } label: {
                        Text("Restore to Default")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.bordered)
                    .listRowBackground(Color.clear)
                    .tint(.primary)
                } footer: {
                    Text("Toggle the checkmark to hide or show a collection, and drag the handles to reorder. These settings apply only on this device in Clic and do not sync to another device or the Sonos app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .fontWeight(.semibold)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func toggleVisibility(for item: SectionConfiguration<SectionID>.SectionItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isVisible.toggle()
            updateConfiguration()
        }
    }
    
    private func updateOrder() {
        for (index, _) in items.enumerated() {
            items[index].order = index
        }
        updateConfiguration()
    }
    
    private func updateConfiguration() {
        configuration.sections = items
    }
    
    private func restoreDefaults() {
        // Sort items by their section enum order (allCases order) and reset visibility
        let sortedSections = SectionID.allCases.compactMap { section in
            items.first { $0.id == section.rawValue }
        }
        
        // Reset visibility and order
        items = sortedSections.enumerated().map { index, item in
            var updated = item
            updated.isVisible = true
            updated.order = index
            return updated
        }
        
        updateConfiguration()
    }
}

// MARK: - Reusable Wrapper Views for App Registry

struct ReorderAppleLibrarySectionsView: View {
    @State private var store = SectionConfigurationStores.shared.appleLibrary
    
    var body: some View {
        ReorderSectionsView(configuration: $store.configuration)
    }
}

struct ReorderSpotifyLibrarySectionsView: View {
    @State private var store = SectionConfigurationStores.shared.spotifyLibrary
    
    var body: some View {
        ReorderSectionsView(configuration: $store.configuration)
    }
}

