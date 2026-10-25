import MusicSearchKit
import Nuke
import SonosKit
import SwiftUI

/// Settings ▸ Storage: the caches Cue keeps and can let go of — artwork,
/// and the copy of self-hosted libraries that Songs sorts and searches.
/// Downloads have their own row in Preferences.
struct StorageSettingsScreen: View {
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(AlertService.self) private var alertService

    @State private var cacheSize: Int = 0
    @State private var isClearing = false
    @State private var libraryCacheSize: Int = 0

    var body: some View {
        Form {
            Section {
                Button {
                    Task {
                        isClearing = true
                        await clearImageCache()
                        isClearing = false
                    }
                } label: {
                    Label {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Clear Image Cache")
                                Text(formattedSize(cacheSize))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isClearing {
                                ProgressView()
                            }
                        }
                    } icon: {
                        SettingsIcon(symbol: "photo.stack.fill", colors: [Color(red: 0.95, green: 0.4, blue: 0.4), Color(red: 0.85, green: 0.25, blue: 0.3)])
                    }
                }
                .tint(.primary)
                .disabled(isClearing || cacheSize == 0)
            } footer: {
                Text("Cached artwork. It's downloaded again as it's needed.")
            }

            // Only for people who have a self-hosted library to cache.
            if libraryCacheSize > 0 {
                Section {
                    Button {
                        clearLibraryCache()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Clear Library Cache")
                                Text(formattedSize(libraryCacheSize))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            SettingsIcon(symbol: "externaldrive.fill.badge.xmark", colors: [Color(red: 0.95, green: 0.4, blue: 0.4), Color(red: 0.85, green: 0.25, blue: 0.3)])
                        }
                    }
                    .tint(.primary)
                } footer: {
                    Text("The copy of your music libraries that Songs is sorted and searched from. It syncs again the next time you open Songs.")
                }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task {
            await updateCacheSize()
            libraryCacheSize = SubsonicAPI.shared.cachedSongLibrarySize
                + PlexAPI.shared.cachedSongLibrarySize
                + LibraryBrowseService.cachedSongLibrarySize
        }
    }

    private func clearLibraryCache() {
        HapticManager.shared.fireHaptic(.buttonPress)
        // Drops the in-memory copy and the file together, so the next visit
        // really does re-read the server.
        musicSearchService.clearSubsonicSongCache()
        musicSearchService.clearPlexSongCache()
        LibraryBrowseService.shared.clearSongCache()
        libraryCacheSize = 0
        alertService.showAlert(with: "Cache Cleared", imageName: "trash")
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func updateCacheSize() async {
        if let dataCache = try? DataCache(name: "com.cue.imageCache") {
            cacheSize = dataCache.totalSize
        }
    }

    private func clearImageCache() async {
        HapticManager.shared.fireHaptic(.buttonPress)
        ImageCache.shared.removeAll()
        if let dataCache = try? DataCache(name: "com.cue.imageCache") {
            dataCache.removeAll()
            dataCache.flush()
        }
        // Zero at once: it was just emptied.
        cacheSize = 0
        alertService.showAlert(with: "Cache Cleared", imageName: "trash")
    }
}
