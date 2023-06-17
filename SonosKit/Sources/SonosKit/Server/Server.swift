import Foundation
import Network
import UIKit

public final class HTTPServer {
    var listener : NWListener?
    let queue = DispatchQueue(label: "HTTP Server Queue")
    var connected : Bool = false
    let nwParms = NWParameters.tcp

    public var handler: ((String, String) -> Void)?

    public func start() {
        let monitor = IPMonitor(ipType: .ipv4)
        monitor.pathUpdateHandler = { status in
          print("\(status.debugDescription)")
        }
        listener = try! NWListener(using: nwParms, on: 9094)
        listener?.newConnectionHandler = { [weak self] (newConnection ) in
            print("**** New Connection added")
            if let strongSelf = self {
                newConnection.start(queue: strongSelf.queue)
                strongSelf.receive(on: newConnection)
            }
        }
    
        listener?.stateUpdateHandler = { (newState) in
            switch newState {
            case .ready:
                print("Listener: ✅ Ready and listens on port: \(self.listener?.port?.debugDescription ?? "-")")
            default:
                break
            }
        }

        listener?.start(queue: queue)
    }

    func receive(on connection: NWConnection) {
        connection.receiveMessage { content, contentContext, isComplete, error in
            guard let receivedData = content else {
                print("**** content is nil")
                return
            }

            let dataString = String(decoding: receivedData, as: UTF8.self)
            print("**** received data = \(dataString)")

            let c = dataString.components(separatedBy: "\r\n\r\n")
//            print(c)
//            XMLParserSonos().parseRendererControl(xml: c[1])

            let endpoint = connection.currentPath?.remoteEndpoint?.debugDescription.components(separatedBy: ":")
            let response = "HTTP/1.1 200 OK\r\n\r\n"
            let data = response.data(using: .utf8)!

            self.handler?(endpoint?[0] ?? "", c[1])
            connection.send(content: data, completion: .contentProcessed({ error in
                   if let error = error {
                       print("Error sending response: \(error)")
                   } else {
                       print("Response sent successfully")
                   }
                connection.cancel()

               }))

        }
    }
}

func getIPAddress() -> String? {
    var address : String?

    // Get list of all interfaces on the local machine:
    var ifaddr : UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return nil }
    guard let firstAddr = ifaddr else { return nil }

    // For each interface ...
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee

        // Check for IPv4 or IPv6 interface:
        let addrFamily = interface.ifa_addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

            // Check interface name:
            // wifi = ["en0"]
            // wired = ["en2", "en3", "en4"]
            // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]

            let name = String(cString: interface.ifa_name)
            if  name == "en0" || name == "en2" || name == "en3" || name == "en4" || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3" {

                // Convert interface address to a human readable string:
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
                address = String(cString: hostname)

            }
        }
    }
    freeifaddrs(ifaddr)

    return address
}
