import Defaults
import Foundation
import Observation
import SonosKit
import SubscriptionKit

@Observable
final class Storage<Object: Codable> {
    private var cachedObjects: [Object]?
    private let key: String
    private let limit: Int?
    
    var object: [Object] {
        didSet {
            // Apply limit only if one is set
            let limitedObjects = limit != nil ? Array(object.suffix(limit!)) : object
            
            // Persist to UserDefaults when the value changes
            if let data = try? JSONEncoder().encode(limitedObjects) {
                UserDefaults.standard.set(data, forKey: key)
            }
            // Update cache
            cachedObjects = limitedObjects
        }
    }
    
    init(_ key: String, limit: Int? = 3) {
        self.key = key
        self.limit = limit
        
        // Load from UserDefaults on initialization
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedItems = try? JSONDecoder().decode([Object].self, from: data) {
            // Apply limit to loaded data only if one is set
            let limitedItems = limit != nil ? Array(decodedItems.suffix(limit!)) : decodedItems
            self.object = limitedItems
            self.cachedObjects = limitedItems
        } else {
            self.object = []
            self.cachedObjects = []
        }
    }
    
    // Convenience method to get cached value without triggering didSet
    var cachedObject: [Object] {
        if let cached = cachedObjects {
            return cached
        }
        // Fallback to UserDefaults if cache is nil
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedItems = try? JSONDecoder().decode([Object].self, from: data) {
            let limitedItems = limit != nil ? Array(decodedItems.suffix(limit!)) : decodedItems
            cachedObjects = limitedItems
            return limitedItems
        }
        return []
    }
    
    // Method to add a new object while respecting the limit
    func add(_ newObject: Object) {
        var currentObjects = object
        currentObjects.append(newObject)
        // The didSet will automatically apply the limit
        object = currentObjects
    }
    
    // Method to clear cache and reload from UserDefaults
    func refreshFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedItems = try? JSONDecoder().decode([Object].self, from: data) {
            let limitedItems = limit != nil ? Array(decodedItems.suffix(limit!)) : decodedItems
            self.object = limitedItems
            self.cachedObjects = limitedItems
        }
    }
    
    // Method to clear both cache and UserDefaults
    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        cachedObjects = nil
        object = []
    }
}
