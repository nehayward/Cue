import SwiftUI
import SonosKit
import MusicSearchKit

struct SoundCloudBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SonosService.self) private var sonosService
    @Environment(SoundCloudBrowseService.self) private var soundCloudBrowseService

    @State private var router = Router.browse
    @State private var configStore = SectionConfigurationStores.shared.soundcloudLibrary

    private var isEmpty: Bool {
        soundCloudBrowseService.likedTracks.isEmpty && soundCloudBrowseService.likedPlaylists.isEmpty
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if isEmpty, let error = soundCloudBrowseService.error {
                    errorSection(error)
                } else if isEmpty, !soundCloudBrowseService.isLoading {
                    emptySection
                } else {
                    ForEach(configStore.configuration.visibleSections(), id: \.self) { section in
                        sectionView(for: section)
                    }
                }
            }
            .listSectionSpacing(4)
            .listStyle(.plain)
            .headerProminence(.increased)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("SoundCloud Library")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await updateSoundCloudBrowseService()
            }
            .toolbar {
#if !os(visionOS)
                if #available(iOS 26.0, visionOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
#endif
                ToolbarItem {
                    Button {
                        router.presentedSheet = .reorderSoundCloudLibrarySections
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease")
                            .labelStyle(.iconOnly)
                    }
                }
#if !os(visionOS)
                if #available(iOS 26.0, visionOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
#endif
                ToolbarItem {
                    MediaSelector()
                        .environment(router)
                }
            }
#if !targetEnvironment(macCatalyst)
            .addDismiss {
                dismiss()
                Router.main.inspectorSheet = nil
            }
#endif
            .refreshable {
                Task {
                    await soundCloudBrowseService.refresh()
                }
            }
            .withAppRouter()
        }
        .overlay {
            if soundCloudBrowseService.isLoading, isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                await updateSoundCloudBrowseService()
            }
        }
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    @ViewBuilder
    private func sectionView(for section: SoundCloudLibrarySection) -> some View {
        switch section {
        case .likedSongs:
            Section {
                NavigationLink(value: RouterDestination.playableList(title: "SoundCloud Liked Tracks", playAllItem: .soundCloudLikes, showSectionIndex: false, action: { offset in
                    if offset >= soundCloudBrowseService.likedTracks.count && soundCloudBrowseService.canLoadMore {
                        await soundCloudBrowseService.loadMoreTracks()
                    }
                    return Array(soundCloudBrowseService.likedTracks.prefix(offset + 50))
                })) {
                    Text("Liked Songs")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                .tag(UUID().uuidString)
                LazyVGrid(columns: [.init(), .init()]) {
                    ForEach(soundCloudBrowseService.likedTracks.prefix(7)) { item in
                        PlayableContentRowView(item: item)
                            .buttonStyle(.plain)
                            .geometryGroup()
                    }
                    if !soundCloudBrowseService.likedTracks.isEmpty {
                        PlayAllButtonView(item: .soundCloudLikes)
                            .transition(.identity)
                    }
                }
            }
            .listRowInsets(.default)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowSpacing(0)

        case .playlists:
            Section {
                NavigationLink(value: RouterDestination.playableList(title: "SoundCloud Playlists", showSectionIndex: false, action: { offset in
                    if offset >= soundCloudBrowseService.likedPlaylists.count && soundCloudBrowseService.canLoadMorePlaylists {
                        await soundCloudBrowseService.loadMorePlaylists()
                    }
                    return Array(soundCloudBrowseService.likedPlaylists.prefix(offset + 50))
                })) {
                    Text("Playlists")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                .tag(UUID().uuidString)

                LazyVGrid(columns: [.init(), .init()]) {
                    ForEach(soundCloudBrowseService.likedPlaylists.prefix(8)) { item in
                        PlayableContentRowView(item: item)
                    }
                }
                .listRowInsets(.default)
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
    }

    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                Text("Error Loading SoundCloud")
                    .font(.headline)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task {
                        await updateSoundCloudBrowseService()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var emptySection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("No Liked Tracks")
                    .font(.headline)

                Text("Your SoundCloud liked tracks will appear here when you authenticate.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func updateSoundCloudBrowseService() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await soundCloudBrowseService.updateLikedTracks() }
            group.addTask { await soundCloudBrowseService.updateLikedPlaylists() }
        }
    }
}

#Preview {
    SoundCloudBrowseScreen()
        .withEnvironments()
}
