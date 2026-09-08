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
                if !library.isConfigured {
                    // No folder yet: the one way in is from here.
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
                } else if !library.isScanning, library.songs.isEmpty {
                    // A folder with nothing in it: empty collection rows would
                    // only send the user into five empty lists, so the page
                    // says what to do instead — fill the folder, or pick
                    // another.
                    ContentUnavailableView {
                        Label("No Music in \(library.folderName ?? "the Folder")", systemImage: "folder")
                    } description: {
                        Text("Add music to the folder and rescan, or choose a different folder. Files play on this device.")
                    } actions: {
                        Button {
                            router.presentedSheet = .filesManagement
                        } label: {
                            Text("Choose Folder")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            Task { await library.scan() }
                        } label: {
                            Text("Rescan")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
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
                            Text(count == 1 ? "1 song" : "\(count.formatted()) songs")
                                .foregroundStyle(.secondary)
                        }
                        if library.pendingDownloadCount > 0 {
                            Label {
                                Text(library.pendingDownloadCount == 1
                                     ? "1 song is in iCloud only."
                                     : "\(library.pendingDownloadCount.formatted()) songs are in iCloud only.")
                            } icon: {
                                Image(systemName: "icloud.and.arrow.down")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(library.folderName ?? "Folder")
                    } footer: {
                        Text("Pull down to rescan after adding music. Playlists you make here are saved as .m3u files in the folder. Files play on this device. Change the folder in Settings › Services.")
                    }
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
                // The plus stands on its own, apart from the provider menu:
                // a fixed spacer splits the trailing group in two. No
                // Manage Folder button up here — the folder is chosen from
                // the empty state and changed in Settings › Services.
                if library.isConfigured {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            router.presentedSheet = .newPlaylist(service: .files)
                        } label: {
                            Label("New Playlist", systemImage: "plus")
                                .labelStyle(.iconOnly)
                        }
                    }
#if !os(visionOS)
                    if #available(iOS 26.0, visionOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
#endif
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
