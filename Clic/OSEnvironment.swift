import Foundation
import UIKit

enum OSEnvironment {
    static let pad: Bool = UIDevice.current.userInterfaceIdiom == .pad
    static let versionInfo: String = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
}
