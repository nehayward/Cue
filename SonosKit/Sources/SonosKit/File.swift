//import Foundation
//import Network
//
//class SonosDiscovery {
//    var ips: [String] = []
//    var queue = DispatchQueue(label: "com.example.sonostracker")
//    var discoveryTimer: Timer?
//    let discoveryMessage = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: ssdp:discover\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\nMX: 1\r\n\r\n"
//
//    func discover() {
//        
//        let group = try! NWEndpointGroup.init(host: "239.255.255.250", port: 1900)
//        let connection = group.makeConnection()
//        let content = discoveryMessage.data(using: .utf8)
//        let completion = NWConnection.SendCompletion.contentProcessed(({ (error) in
//            if let error = error {
//                print("Error sending message: \(error)")
//            }
//        }))
//        connection.send(content: content, completion: completion)
//
//        self.discoveryTimer?.invalidate()
//        self.queue.asyncAfter(deadline: .now() + 5) {
//            connection.cancel()
//        }
//
//        let receiveHandler: ((Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void) = { (data, context, isComplete, error) in
//            guard let data = data else { return }
//            let response = String(decoding: data, as: UTF8.self)
//            if let ipAddress = self.extractIPAddress(from: response) {
//                self.ips.append(ipAddress)
//            }
//        }
//
//        connection.receiveMessage { (data, context, isComplete, error) in
//            receiveHandler(data, context, isComplete, error)
//            if isComplete {
//                self.discoveryTimer?.invalidate()
//                connection.cancel()
//            }
//        }
//
//        self.discoveryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { (_) in
//            connection.cancel()
//        }
//    }
//
//    func extractIPAddress(from response: String) -> String? {
//        let pattern = "LOCATION: http://([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+):"
//        let regex = try! NSRegularExpression(pattern: pattern, options: [])
//        let range = NSRange(response.startIndex..<response.endIndex, in: response)
//        if let match = regex.firstMatch(in: response, options: [], range: range) {
//            let ipAddressRange = match.range(at: 1)
//            if let ipAddressRange = Range(ipAddressRange, in: response) {
//                return String(response[ipAddressRange])
//            }
//        }
//        return nil
//    }
//}
