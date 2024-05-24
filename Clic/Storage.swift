import Defaults
import Foundation
import Observation
import SonosKit
import SubscriptionKit

@Observable
final class Storage<Object: Codable> {
    var object: [Object] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decodedItems = try? JSONDecoder().decode([Object].self, from: data) else {
                return []
            }
            return decodedItems
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    private let key: String

    init(_ key: String) {
        self.key = key
    }
}
