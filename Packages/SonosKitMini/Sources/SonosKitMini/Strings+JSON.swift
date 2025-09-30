import Foundation

extension String {
    var prettyPrinted: String {
        #if DEBUG
        if let json = try? JSONSerialization.jsonObject(with: self.data(using: .utf8)!, options: .mutableContainers),
           let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            return String(decoding: jsonData, as: UTF8.self)
        } else {
            print("json data malformed")
        }
        #endif
        return ""
    }
}
