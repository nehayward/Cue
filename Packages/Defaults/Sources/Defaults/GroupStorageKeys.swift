import Foundation

public enum GroupStorageKeys {
    public static let storage = UserDefaults(suiteName: GroupStorageKeys.name)
    
    public static let name = "group.com.clic"
    public static let hasOnboarded = "\(Prefix.id).hasOnboarded"
}
