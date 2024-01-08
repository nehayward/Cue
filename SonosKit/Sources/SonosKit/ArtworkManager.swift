import Foundation
import UIKit

public final class ArtworkManager {
    public static var shared = ArtworkManager()

    private let containerURL: URL

    public init() {
        self.containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.clic")!
    }

    public func downScale(coordinatorRoom: String,  url: URL?) async {
        let fileURL = containerURL.appendingPathComponent("\(coordinatorRoom).jpg")

        guard let url = url else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let imageData = try? await URLSession.shared.data(from: url).0 else { return }
        guard let image = UIImage(data: imageData) else { return }

        let size = image.size
        let targetSize  = CGSize(width: 300, height: 300)
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let newSize = widthRatio > heightRatio ? CGSize(width: size.width * heightRatio, height: size.height * heightRatio) : CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        let data = resizedImage?.jpegData(compressionQuality: 1)

        do {
            try data?.write(to: fileURL)
            print("Image saved successfully to \(fileURL)")
        } catch {
            print("Error saving image: \(error)")
        }
    }

    public func removeArtwork(coordinatorRoom: String) {
        let fileURL = containerURL.appendingPathComponent("\(coordinatorRoom).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func getImageData(name: String) -> Data? {
        let fileURL = containerURL.appendingPathComponent("\(name).jpg")
        return try? Data(contentsOf: fileURL)
    }

    public func getImage(name: String) -> UIImage? {
        let fileURL = containerURL.appendingPathComponent("\(name).jpg")
        if let data = try? Data(contentsOf: fileURL) {
            return UIImage(data: data)
        }
        return nil
    }
}
