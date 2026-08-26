import Foundation
import Observation
import SonosKit

/// Downloads Plex tracks to this device for offline playback. Plex serves the
/// user's own DRM-free files (`previewURL` is a direct, token-authenticated
/// URL to the track's media file), so unlike Apple Music we can simply store
/// the file and hand `AVPlayer` the local copy — airplane mode included.
///
/// Files live in Application Support/PlexDownloads as `<track id>.<ext>`; the
/// directory is scanned once at launch to rebuild `downloadedKeys`.
@MainActor
@Observable
final class PlexDownloadService {
    static let shared = PlexDownloadService()

    /// Track keys with a completed local file.
    private(set) var downloadedKeys: Set<String> = []
    /// Track keys currently downloading.
    private(set) var downloading: Set<String> = []

    @ObservationIgnored private let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = support.appendingPathComponent("PlexDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        scan()
    }

    // MARK: - Queries

    func isDownloaded(_ item: PlayableContent) -> Bool {
        downloadedKeys.contains(Self.key(for: item))
    }

    func isDownloading(_ item: PlayableContent) -> Bool {
        downloading.contains(Self.key(for: item))
    }

    /// The local file for a downloaded track, or nil. Playback prefers this
    /// over the server URL, so downloaded tracks work away from the server.
    func localURL(for item: PlayableContent) -> URL? {
        guard item.content.service == .plex else { return nil }
        let key = Self.key(for: item)
        guard downloadedKeys.contains(key) else { return nil }
        return files().first { $0.deletingPathExtension().lastPathComponent == key }
    }

    // MARK: - Downloading

    func download(_ item: PlayableContent) {
        guard item.content.service == .plex, let url = item.previewURL else { return }
        let key = Self.key(for: item)
        guard !downloadedKeys.contains(key), !downloading.contains(key) else { return }
        downloading.insert(key)

        Task {
            defer { downloading.remove(key) }
            do {
                let (temporary, _) = try await URLSession.shared.download(from: url)
                let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
                let destination = directory.appendingPathComponent("\(key).\(ext)")
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
                downloadedKeys.insert(key)
            } catch {
                print("Plex download failed for \(item.title): \(error)")
            }
        }
    }

    func removeDownload(_ item: PlayableContent) {
        guard let url = localURL(for: item) else { return }
        try? FileManager.default.removeItem(at: url)
        downloadedKeys.remove(Self.key(for: item))
    }

    // MARK: - Storage

    /// Filesystem-safe key for a track: its Plex id with path separators and
    /// the extension dot neutralized.
    private static func key(for item: PlayableContent) -> String {
        item.content.id
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    private func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func scan() {
        downloadedKeys = Set(files().map { $0.deletingPathExtension().lastPathComponent })
    }
}
