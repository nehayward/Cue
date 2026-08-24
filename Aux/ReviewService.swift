import Foundation
import StoreKit
#if targetEnvironment(macCatalyst) || os(macOS)
import Security
#endif

final class ReviewCoordinator {
    struct UserDefaultsKeys {
        static let processCompletedCountKey = "processCompletedCountKey"
        static let lastVersionPromptedForReviewKey = "lastVersionPromptedForReviewKey"
    }

    static let shared = ReviewCoordinator()
    let identifier = "[ReviewCoordinator] "
    let debug = false

    private func isAppStoreReceiptSandbox() -> Bool {
        if isSimulator() {
            return false
        } else {
            #if targetEnvironment(macCatalyst) || os(macOS)
            return Bundle.main.isTestFlight
            #else
            return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            #endif
        }
    }

    private func isSimulator() -> Bool {
        #if arch(i386) || arch(x86_64)
        return true
        #else
        return false
        #endif
    }

    func requestReview() {
        #if DEBUG
        return
        #endif
        // Skip review request if running in TestFlight
        guard !isAppStoreReceiptSandbox() else {
            debugPrint("\(self.identifier) | Skipping review request in TestFlight")
            return
        }

        var lastVersionPromptedForReview = "0"
        if let version = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastVersionPromptedForReviewKey) {
            lastVersionPromptedForReview = version
        }

        // Get the current bundle version for the app
        let infoDictionaryKey = kCFBundleVersionKey as String
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String
        else { fatalError("Expected to find a bundle version in the info dictionary") }

        guard currentVersion != lastVersionPromptedForReview else {
            debugPrint("\(self.identifier) | Already asked to review this version")
            UserDefaults.standard.set(0, forKey: UserDefaultsKeys.processCompletedCountKey)
            return
        }

        //  If the count has not yet been stored, this will return 0
        var count = UserDefaults.standard.integer(forKey: UserDefaultsKeys.processCompletedCountKey)
        count += 1
        UserDefaults.standard.set(count, forKey: UserDefaultsKeys.processCompletedCountKey)

        debugPrint("\(self.identifier) | Process completed \(count) time(s)")

        debugPrint("\(self.identifier) | lastVersionPromptedForReview \(lastVersionPromptedForReview)")

        // Has the process been completed several times and the user has not already been prompted for this version?
        if count >= 3 && currentVersion != lastVersionPromptedForReview {
            debugPrint("\(self.identifier) | valid review request")
            if let scene = UIApplication
                .shared
                .connectedScenes
                .flatMap({ ($0 as? UIWindowScene)?.windows ?? [] }).first?.windowScene {

                SKStoreReviewController.requestReview(in: scene)
                UserDefaults.standard.set(currentVersion, forKey: UserDefaultsKeys.lastVersionPromptedForReviewKey)
                UserDefaults.standard.set(0, forKey: UserDefaultsKeys.processCompletedCountKey)
            }
        }
    }
}

#if targetEnvironment(macCatalyst) || os(macOS)
extension Bundle {
    /// Returns whether the bundle was signed for TestFlight beta distribution by checking
    /// the existence of a specific extension (marker OID) on the code signing certificate.
    ///
    /// This routine is inspired by the source code from ProcInfo, the underlying library
    /// of the WhatsYourSign code signature checking tool developed by Objective-See. Initially,
    /// it checked the common name but was changed to an extension check to make it more
    /// future-proof.
    ///
    /// For more information, see the following references:
    /// - https://github.com/objective-see/ProcInfo/blob/master/procInfo/Signing.m#L184-L247
    /// - https://gist.github.com/lukaskubanek/cbfcab29c0c93e0e9e0a16ab09586996#gistcomment-3993808
    internal var isTestFlight: Bool {
        var status = noErr

        var code: SecStaticCode?
        status = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code)

        guard status == noErr, let code = code else { return false }

        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(
            "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.25.1]" as CFString,
            [], // default
            &requirement
        )

        guard status == noErr, let requirement = requirement else { return false }

        status = SecStaticCodeCheckValidity(
            code,
            [], // default
            requirement
        )

        return status == errSecSuccess
    }
}
#endif

