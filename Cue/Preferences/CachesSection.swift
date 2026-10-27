import MusicSearchKit
import Nuke
import SonosKit
import SwiftUI

/// The caches Cue keeps and can let go of — artwork, and the copy of
/// self-hosted libraries that Songs sorts and searches — at the foot of
/// Downloads ▸ Settings, with everything else that takes room on this
/// device.
struct CachesSection: View {
    @State private var cacheSize: Int = 0
    @State private var isClearing = false
    @State private var libraryCacheSize: Int = 0

    var body: some View {
        Section {
            Button {
                Task {
                    isClearing = true
                    await clearImageCache()
                    isClearing = false
                }
            } label: {
                LabeledContent {
                    if isClearing {
                        ProgressView()
                    } else {
                        Text(formattedSize(cacheSize))
                    }
                } label: {
                    Label("Clear Image Cache", systemImage: "photo.stack")
                }
            }
            .tint(.primary)
            .disabled(isClearing || cacheSize == 0)

            // Only for people who have a self-hosted library to cache.
            if libraryCacheSize > 0 {
                Button {
                    clearLibraryCache()
                } label: {
                    LabeledContent {
                        Text(formattedSize(libraryCacheSize))
                    } label: {
                        Label("Clear Library Cache", systemImage: "externaldrive.badge.xmark")
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Caches")
        } footer: {
            Text(libraryCacheSize > 0
                 ? "Artwork is downloaded again as it's needed. The library cache is the copy of your music libraries that Songs is sorted and searched from; it syncs again the next time you open Songs."
                 : "Artwork is downloaded again as it's needed.")
        }
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
        MusicSearchService.shared.clearSubsonicSongCache()
        MusicSearchService.shared.clearPlexSongCache()
        LibraryBrowseService.shared.clearSongCache()
        libraryCacheSize = 0
        AlertService.shared.showAlert(with: "Cache Cleared", imageName: "trash")
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
        AlertService.shared.showAlert(with: "Cache Cleared", imageName: "trash")
    }
}
