import Foundation
import Nuke
#if canImport(UIKit)
import UIKit
#endif
public final class ArtworkManager {
    public static var shared = ArtworkManager()

    private let containerURL: URL

    public init() {
        self.containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.clic")!
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
            guard let newData = try await downloadAndProcessImage(from: url) else {
                print("No image data downloaded.")
                return
            }

            try newData.write(to: fileURL, options: .atomic)
            try setTrackID(trackID, for: fileURL)
        } catch {
            print("Error saving image: \(error)")
        }
    #endif
    }
    
    private func setTrackID(_ id: String, for fileURL: URL) throws {
        let data = id.data(using: .utf8)!
        let path = fileURL.path
        let result = setxattr(path, "com.clic.trackid", (data as NSData).bytes, data.count, 0, 0)
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
    }
    
    private func getTrackID(for fileURL: URL) -> String? {
        let path = fileURL.path
        let size = getxattr(path, "com.clic.trackid", nil, 0, 0, 0)
        guard size >= 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let result = getxattr(path, "com.clic.trackid", &buffer, buffer.count, 0, 0)
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
        return imageContainer.jpegData(compressionQuality: 1)
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
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.clic")!.appendingPathComponent("\(name).jpg")
}
