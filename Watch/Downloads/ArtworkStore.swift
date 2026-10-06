import Foundation
import ImageIO
import Observation
import UIKit

/// Covers for what's on the watch, fetched once and kept in Caches, so the
/// library shows them away from any network. Decoded small: a list row
/// needs a fraction of what a server sends.
@MainActor
@Observable
final class ArtworkStore {
    static let shared = ArtworkStore()

    /// Moves on as covers arrive, so views that asked for one look again.
    private(set) var revision = 0

    @ObservationIgnored private var memory: [String: UIImage] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    private init() {}

    /// The cover for a URL if it's here: memory first, then disk.
    func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        _ = revision
        let name = Self.name(for: url)
        if let image = memory[name] { return image }
        guard let data = try? Data(contentsOf: Self.fileURL(name)), let image = Self.thumbnail(from: data) else { return nil }
        memory[name] = image
        return image
    }

    /// Fetches a cover that isn't here yet.
    func load(_ url: URL?) {
        guard let url else { return }
        let name = Self.name(for: url)
        guard memory[name] == nil, !loading.contains(name),
              !FileManager.default.fileExists(atPath: Self.fileURL(name).path) else { return }
        loading.insert(name)
        Task { _ = await fetch(url) }
    }

    /// The cover, from here or fetched now; nil when it can't be had.
    func fetch(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let image = image(for: url) { return image }
        let name = Self.name(for: url)
        loading.insert(name)
        defer { loading.remove(name) }
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200 ..< 300).contains(status), let image = Self.thumbnail(from: data) else { return nil }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL(name), options: .atomic)
        memory[name] = image
        revision += 1
        return image
    }

    func prefetch(_ urls: [URL]) {
        urls.forEach { load($0) }
    }

    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Artwork", isDirectory: true)
    }

    private static func fileURL(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// A stable file name for a URL (FNV-1a): `hashValue` changes from
    /// launch to launch.
    private static func name(for url: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    private static func thumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
