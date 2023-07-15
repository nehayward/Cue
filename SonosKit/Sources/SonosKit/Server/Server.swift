import Foundation
import Network
import UIKit

public final class HTTPServer {

    var udpListener: NWListener?
    var backgroundQueueUdpListener = DispatchQueue(label: "udp-lis.bg.queue", attributes: [])
    var backgroundQueueUdpConnection = DispatchQueue(label: "udp-con.bg.queue", attributes: [])
    var connections = [NWConnection]()

    let params = NWParameters(tls: nil, tcp: {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle   = 2
        return tcpOptions
    }())

    public var handler: ((String, String) -> Void)?
    public var zoneHandler: ((String, String) -> Void)?

    public func start() {
        print(IPLookup.shared.deviceIPV4)
        guard self.udpListener == nil else {
             print("Already listening. Not starting again")
             return
         }

        do {
            self.udpListener = try NWListener(using: params, on: 9094)

              self.udpListener?.stateUpdateHandler = { (listenerState) in
                  print("👂🏼👂🏼👂🏼 NWListener Handler called")
                  switch listenerState {
                  case .setup:
                      print("Listener: Setup")
                  case .waiting(let error):
                      print("Listener: Waiting \(error)")
                  case .ready:
                      print("Listener: ✅ Ready and listens on port: \(self.udpListener?.port?.debugDescription ?? "-")")
                  case .failed(let error):
                      print("Listener: Failed \(error)")
                      self.udpListener = nil
                  case .cancelled:
                      print("Listener: 🛑 Cancelled by myOffButton")
                      for connection in self.connections {
                          connection.cancel()
                      }
                      self.udpListener = nil
                  default:
                      break;

                  }
              }

              self.udpListener?.start(queue: backgroundQueueUdpListener)
              self.udpListener?.newConnectionHandler = { (incomingUdpConnection) in
                  print("📞📞📞 NWConnection Handler called ")
                  incomingUdpConnection.stateUpdateHandler = { (udpConnectionState) in

                      switch udpConnectionState {
                      case .setup:
                          print("Connection: 👨🏼‍💻 setup")
                      case .waiting(let error):
                          print("Connection: ⏰ waiting: \(error)")
                      case .ready:
                          print("Connection: ✅ ready")
                          self.connections.append(incomingUdpConnection)
                          self.receive(on: incomingUdpConnection)
                      case .failed(let error):
                          print("Connection: 🔥 failed: \(error)")
                          self.connections.removeAll(where: {incomingUdpConnection === $0})
                      case .cancelled:
                          print("Connection: 🛑 cancelled")
                          self.connections.removeAll(where: {incomingUdpConnection === $0})
                      default:
                          break
                      }
                  }

                  incomingUdpConnection.start(queue: self.backgroundQueueUdpConnection)
              }

          } catch {
              print("🧨🧨🧨 CATCH")
          }
    }

    func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 0, maximumLength: 1200000) { (content, context, isComplete, error) in
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
            if endpoint?.count ?? 0 > 1, c.count > 1 {
                self.handler?(endpoint?[0] ?? "", c[1])
                self.zoneHandler?(endpoint?[0] ?? "", c[1])
            }
            if isComplete {
                connection.send(content: data, completion: .contentProcessed({ error in
                    if let error = error {
                        print("Error sending response: \(error)")
                    } else {
                        print("Response sent successfully")
                    }
                    self.receive(on: connection)
                }))
            }
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
