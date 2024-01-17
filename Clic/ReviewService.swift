import Foundation
import StoreKit

final class ReviewService {
    static var shared = ReviewService()

    private var numberOfOpens: Int {
        get {
            UserDefaults.standard.integer(forKey: "com.clic.numberOfOpens")
        } set {
            UserDefaults.standard.set(newValue, forKey: "com.clic.numberOfOpens")
        }
    }

    private var shouldAskForRating: Bool {
        numberOfOpens > 4 && !OSEnvironment.isDebugging
    }

    func askForRatingIfNeeded() {
        guard shouldAskForRating else {
            numberOfOpens += 1
            return
        }
        askForRating()
    }

    private func askForRating() {
        #if os(macOS)
            SKStoreReviewController.requestReview()
        #else
            guard let scene = UIApplication.shared.foregroundActiveScene else { return }
            SKStoreReviewController.requestReview(in: scene)
        #endif
    }
}

extension UIApplication {
    var foregroundActiveScene: UIWindowScene? {
        connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }
}
