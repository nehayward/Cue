import Foundation

final class ReviewService {
    private var askAfterDate: Date { 
        get {
            UserDefaults.standard.object(forKey: "com.clic.installDate") as? Date ?? defaultAskDate
        } set {
            UserDefaults.standard.set(newValue, forKey: "com.clic.installDate")
        }
    }

    func askForRequest() -> Bool {
        if askAfterDate < Date.now {
            askAfterDate = Calendar.current.date(byAdding: .month, value: 2, to: .now)!
            return true
        }
        return false
    }

    fileprivate var defaultAskDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: 3,
            to: .now
        )!
    }
}
