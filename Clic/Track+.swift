import Foundation
import SonosKit
import UIKit

extension Track {
    @MainActor
    var safeURL: URL? {
#if canImport(UIKit)
        for url in musicServiceOpenURLs.compactMap({$0}) {
            if UIApplication.shared.canOpenURL(url) {
                return url
            }
        }
#endif
        return nil
    }
}
