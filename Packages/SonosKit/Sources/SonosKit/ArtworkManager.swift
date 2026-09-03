import Foundation
import Nuke
#if canImport(UIKit)
import UIKit
#endif

public final class ArtworkManager {
    public static var shared = ArtworkManager()

    private let containerURL: URL
    
    // Cache to track failed URLs and their retry attempts
    private var failedURLCache: [URL: (attempts: Int, lastAttempt: Date)] = [:]
    private let maxRetryAttempts = 3
    /// How long a URL that exhausted its retries stays blacklisted. Artwork
    /// hosts fail transiently (Sonos Radio's proxy 503s under load), so a
    /// permanent per-session blacklist would keep art broken long after the
    /// host recovers.
    private let failedURLRetryCooldown: TimeInterval = 3600
    private let retryCacheQueue = DispatchQueue(label: "com.cue.artwork.retrycache", attributes: .concurrent)

    public init() {
        self.containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.dance.cue")!
    }

    public func downScale(coordinatorRoom: String, url: URL?, trackID: String) async {
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let fileURL = getFileURL(for: coordinatorRoom)

        // If no URL is provided, remove the artwork
        guard let url = url else {
            removeArtwork(coordinatorRoom: coordinatorRoom)
            return
        }

        // Check existing trackID before downloading
        let existingTrackID = getTrackID(for: fileURL)
        if existingTrackID == trackID { return }

        do {
            guard let newData = try await downloadAndProcessImageWithRetry(from: url) else {
                return
            }

            try newData.write(to: fileURL, options: .atomic)
            try setTrackID(trackID, for: fileURL)
            
            // Clear failed cache entry on success
            clearFailedURLCache(for: url)
        } catch {
            print("Error saving image: \(error)")
        }
    #endif
    }
    
    private func downloadAndProcessImageWithRetry(from url: URL) async throws -> Data? {
        // Check if this URL has exceeded max retry attempts
        if let failedEntry = getFailedURLCache(for: url), failedEntry.attempts >= maxRetryAttempts {
            guard Date().timeIntervalSince(failedEntry.lastAttempt) >= failedURLRetryCooldown else {
                return nil
            }
            // Cooldown passed — give the URL a fresh set of attempts.
            clearFailedURLCache(for: url)
        }
        
        var lastError: Error?
        
        for attempt in 1...maxRetryAttempts {
            do {
                let imageData = try await downloadAndProcessImage(from: url)
                if imageData != nil {
                    print("Successfully downloaded image from \(url) on attempt \(attempt)")
                    return imageData
                } else {
                    throw NSError(domain: "ArtworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No image data received"])
                }
            } catch {
                lastError = error
                print("Failed to download image from \(url) on attempt \(attempt): \(error)")
                
                // Update failed cache
                updateFailedURLCache(for: url, attempt: attempt)
                
                // If this was the last attempt, don't wait
                if attempt < maxRetryAttempts {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = TimeInterval(pow(2.0, Double(attempt - 1)))
                    print("Retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All attempts failed
        print("All \(maxRetryAttempts) attempts failed for URL: \(url)")
        throw lastError ?? NSError(domain: "ArtworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download image after \(maxRetryAttempts) attempts"])
    }
    
    private func updateFailedURLCache(for url: URL, attempt: Int) {
        retryCacheQueue.async(flags: .barrier) {
            self.failedURLCache[url] = (attempts: attempt, lastAttempt: Date())
        }
    }
    
    private func getFailedURLCache(for url: URL) -> (attempts: Int, lastAttempt: Date)? {
        retryCacheQueue.sync {
            return failedURLCache[url]
        }
    }
    
    private func clearFailedURLCache(for url: URL) {
        retryCacheQueue.async(flags: .barrier) {
            self.failedURLCache.removeValue(forKey: url)
        }
    }
    
    // Clean up old failed entries (older than 1 hour)
    public func cleanupFailedURLCache() {
        retryCacheQueue.async(flags: .barrier) {
            let oneHourAgo = Date().addingTimeInterval(-3600)
            self.failedURLCache = self.failedURLCache.filter { _, value in
                value.lastAttempt > oneHourAgo
            }
        }
    }
    
    private func setTrackID(_ id: String, for fileURL: URL) throws {
        let data = id.data(using: .utf8)!
        let path = fileURL.path
        let result = setxattr(path, "com.cue.trackid", (data as NSData).bytes, data.count, 0, 0)
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
    }
    
    private func getTrackID(for fileURL: URL) -> String? {
        let path = fileURL.path
        let size = getxattr(path, "com.cue.trackid", nil, 0, 0, 0)
        guard size >= 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let result = getxattr(path, "com.cue.trackid", &buffer, buffer.count, 0, 0)
        guard result >= 0 else { return nil }

        return String(bytes: buffer, encoding: .utf8)
    }

    private func downloadAndProcessImage(from url: URL) async throws -> Data? {
        let request = ImageRequest(
            url: url,
            processors: [
                ImageProcessors.Resize(
                    size: CGSize(width: 50, height: 50),
                    contentMode: .aspectFit
                )
            ]
        )
        
        let imageContainer = try await ImagePipeline.shared.image(for: request)
        #if canImport(UIKit)
        return imageContainer.jpegData(compressionQuality: 1)
        #endif
        return nil
    }
    
    public func removeArtwork(coordinatorRoom: String) {
        let fileURL = getFileURL(for: coordinatorRoom)
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func getImageData(name: String) -> Data? {
        let fileURL = getFileURL(for: name)
        return try? Data(contentsOf: fileURL)
    }
    
#if canImport(UIKit)
    public func getImage(name: String) -> UIImage? {
        #if DEBUG
        print("HERE")
        if name == "Kitchen + 1" {
            return UIImage(named: "barbie")
        }
        #endif
        let fileURL = getFileURL(for: name)
        if let data = try? Data(contentsOf: fileURL) {
            return UIImage(data: data)
        }
        return nil
    }
#endif
}

private func getFileURL(for name: String) -> URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.dance.cue")!.appendingPathComponent("\(name).jpg")
}
