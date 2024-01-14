import Foundation

final class ReviewService {
    static var shared = ReviewService()

    var numberOfOpens: Int {
        get {
            UserDefaults.standard.integer(forKey: "com.clic.numberOfOpens")
        } set {
            UserDefaults.standard.set(newValue, forKey: "com.clic.numberOfOpens")
        }
    }

    func askForRequest() -> Bool {
        numberOfOpens > 3
    }
}
