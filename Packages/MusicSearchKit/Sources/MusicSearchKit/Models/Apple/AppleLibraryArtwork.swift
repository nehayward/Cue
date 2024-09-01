import Foundation

public struct AppleLibraryArtwork: Codable {
    public let url: URL?
    public func urlWithSize(width: Int, height: Int) -> URL? {
        guard let url = url?.absoluteString.removingPercentEncoding else { return nil }
        let widthPlaceholder = "{w}"
        let heightPlaceholder = "{h}"
        return URL(string: url.replacingOccurrences(of: widthPlaceholder, with: "\(width)")
            .replacingOccurrences(of: heightPlaceholder, with: "\(height)"))
    }
}
