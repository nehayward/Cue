import Foundation
import Nuke
import NukeUI
#if canImport(UIKit)
import UIKit
#endif
public final class ArtworkManager {
    public static var shared = ArtworkManager()

    private let containerURL: URL

    public init() {
        self.containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.clic")!
    }

    public func downScale(coordinatorRoom: String,  url: URL?) async {
#if canImport(UIKit)
        let fileURL = getFileURL(for: coordinatorRoom)

        guard let url = url else {
            removeArtwork(coordinatorRoom: coordinatorRoom)
            return
        }
        
        do {
            let newData = try await downloadAndProcessImage(from: url)
            try await saveImageIfDifferent(newData, to: fileURL)
        } catch {
            print("Error saving image: \(error)")
        }
#endif
    }

    private func downloadAndProcessImage(from url: URL) async throws -> Data? {
        let request = ImageRequest(url: url, processors: [
            ImageProcessors.Resize(size: CGSize(width: 50, height: 50)),
        ])
        
        let image = try await ImagePipeline.shared.image(for: request)
        return image.jpegData(compressionQuality: 1)
    }
    
    private func saveImageIfDifferent(_ newData: Data?, to fileURL: URL) async throws {
        guard let newData else { return }
        
        let existingData = try? Data(contentsOf: fileURL)
        guard existingData != newData else { return }
        
        try newData.write(to: fileURL)
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
