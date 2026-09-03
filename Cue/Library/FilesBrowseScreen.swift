import MusicSearchKit
import SonosKit
import SwiftUI

/// The Files provider's front page: the folder's artists, albums and songs,
/// with the scan's progress underneath. The rows push the same destinations
/// the provider's sidebar tabs show.
struct FilesBrowseScreen: View {
    @Environment(\.dismiss) var dismiss

    @State private var router = Router.browse
    @State private var library = FilesLibraryService.shared

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if library.isConfigured {
                    ForEach(MediaSearchService.files.tabCollections, id: \.self) { collection in
                        if let destination = ProviderLibrary.filesDestination(for: collection) {
                            NavigationLink(value: destination) {
                                Label(collection.title, systemImage: collection.systemImage)
                            }
                        }
                    }

                    Section {
                        if library.isScanning {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text(library.foundCount > 0
                                     ? "Reading tags… \(library.scannedCount) of \(library.foundCount)"
                                     : "Looking for music…")
                                    .monospacedDigit()
                            }
                            .foregroundStyle(.secondary)
                        } else {
                            let count = library.songs.count
                            Text(count == 0
                                 ? "No music found in \(library.folderName ?? "the folder") yet."
                                 : (count == 1 ? "1 song" : "\(count.formatted()) songs"))
                                .foregroundStyle(.secondary)
                        }
                        if library.pendingDownloadCount > 0 {
                            Label {
                                Text(library.pendingDownloadCount == 1
                                     ? "1 file is still downloading from iCloud."
                                     : "\(library.pendingDownloadCount) files are still downloading from iCloud.")
                            } icon: {
                                Image(systemName: "icloud.and.arrow.down")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(library.folderName ?? "Folder")
                    } footer: {
                        Text("Pull down to rescan after adding music. Playlists you make here are saved as .m3u files in the folder. Files play on this device.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Folder Chosen", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Pick a folder of music on this device or in iCloud Drive to browse it here.")
                    } actions: {
                        Button {
                            router.presentedSheet = .filesManagement
                        } label: {
                            Text("Choose Folder")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .contentMargins(.horizontal, 16)
            .miniPlayerOnScrollHandler()
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await library.scanIfNeeded()
            }
            .refreshable {
                await library.scan()
            }
            .withAppRouter()
            .toolbar {
                if library.isConfigured {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            router.presentedSheet = .newPlaylist(service: .files)
                        } label: {
                            Label("New Playlist", systemImage: "plus")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.presentedSheet = .filesManagement
                    } label: {
                        Label("Manage Folder", systemImage: "folder.badge.gearshape")
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }
}

#Preview {
    FilesBrowseScreen()
        .withEnvironments()
}
