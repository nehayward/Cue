import Foundation
import UIKit

enum OSEnvironment {
    static let pad: Bool = UIDevice.current.userInterfaceIdiom == .pad
    static let versionInfo: String = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    static let isPreviews: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    static var isDebugging: Bool {
#if DEBUG
        return true
#endif
        return false
    }
}
