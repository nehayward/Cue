import WatchKit

enum OSEnvironment {
    static let versionInfo: String = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    static let buildNumber: String = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
    static let isPreviews: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    static var isDebugging: Bool {
#if DEBUG
        return true
#endif
        return false
    }
}
