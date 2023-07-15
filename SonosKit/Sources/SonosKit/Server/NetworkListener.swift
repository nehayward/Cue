import Foundation
import Network
import UIKit

class ListenerX {

    private var connection: NWConnection? = nil
    var listener: NWListener?

    func report(_ msg: String) {
        print("server: \(msg)")
    }


    public var handler: ((String, String) -> Void)?
    public var zoneHandler: ((String, String) -> Void)?


    func start() {
        report("start server")


        let tcpOption = NWProtocolTCP.Options()
//        tcpOption.enableKeepalive = true
//        tcpOption.keepaliveIdle = 1
        tcpOption.disableECN = true

        let params = NWParameters(tls: nil, tcp: tcpOption)    /* Configure TLS here */
        params.allowFastOpen = true
        params.allowLocalEndpointReuse = true

        print(IPLookup.shared.deviceIPV4)

        guard listener == nil else {
            print("Already listening. Not starting again")
            return
        }

        listener = try! NWListener(using: params, on: 9094)
        listener?.stateUpdateHandler = stateDidChange
        listener?.newConnectionHandler = didAccept
        listener?.serviceRegistrationUpdateHandler = self.serviceRegistrationUpdateHandler
        listener?.start(queue: .main)

    }

    private func stateDidChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
            report("Server ready service=\(listener?.service) port=\(listener?.port)")
        case .failed(let error):
            report("Server failure, error: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func serviceRegistrationUpdateHandler(_ change: NWListener.ServiceRegistrationChange) {
        report("registration did change: \(change)")
    }

    private func didAccept(nwConnection: NWConnection) {
        report("did accept connection: \(nwConnection)")
        connection = nwConnection
        connection?.stateUpdateHandler = self.stateDidChange
        connection?.start(queue: .main)
        receive()
    }
    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .waiting(let error):
            print(error)
        case .ready:
            report("connection ready")
        case .failed(let error):
            print(error)
        default:
            break
        }
    }

    // functions removed to make space

    var block: Data = Data()

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: Int.max) { (data, context, isComplete, error) in
            if let error = error {
                self.report("connection failed: \(error)")
                return
            }

            if let data = data, !data.isEmpty {
                if self.block.isEmpty {
                    self.block = data
                } else {
                    self.block.append(data)
                }


            }

            if isComplete {
                print(context)
                if self.block.isEmpty {
                    return
                }
                self.report("is complete")
                //                                self.connectionDidEnd()
                self.report("connection did receive, data: \(data)")
                print("**************** Data ******************\n\n")
                let decoded = String(decoding: self.block, as: UTF8.self)
                print(decoded)

                let c = decoded.components(separatedBy: "\r\n\r\n")

                let endpoint = self.connection?.currentPath?.remoteEndpoint?.debugDescription.components(separatedBy: ":")
                let response = "HTTP/1.1 200 OK\r\n\r\n"
                let data = response.data(using: .utf8)!
                if endpoint?.count ?? 0 > 1, c.count > 1 {
                    self.handler?(endpoint?[0] ?? "", c[1])
                    self.zoneHandler?(endpoint?[0] ?? "", c[1])
                }

                print("**************** Data ******************\n\n")
                self.block.removeAll()
                return
            } else {
                self.report("setup next read")
                self.receive()
            }
        }
    }

    func send(data: Data) {
        report("connection will send data: \(data)")
        self.connection?.send(content: data, contentContext: .defaultStream, completion: .contentProcessed( { error in
            if let error = error {

                return
            }
            self.report("connection did send, data: \(data)")
        }))
    }
}
