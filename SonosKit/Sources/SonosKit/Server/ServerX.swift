import Foundation
import Network

final class Server {
    let port: NWEndpoint.Port
    let listener: NWListener

    private var connectionsByID: [Int: ServerConnection] = [:]

    public var zoneHandler: ((String, String) -> Void)?

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
        listener = try! NWListener(using: .tcp, on: self.port)
    }

    func start() throws {
        print("Server starting...")
        listener.stateUpdateHandler = stateDidChange
        listener.newConnectionHandler = didAccept
        listener.start(queue: .global(qos: .userInteractive))
    }

    func stateDidChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
          print("Server ready.")
        case .failed(let error):
            print("Server failure, error: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func didAccept(nwConnection: NWConnection) {
        let connection = ServerConnection(nwConnection: nwConnection)
        connection.zoneHandler = zoneHandler
        self.connectionsByID[connection.id] = connection
        connection.didStopCallback = { _ in
            self.connectionDidStop(connection)
        }
        connection.start()
        connection.send(data: "Welcome you are connection: \(connection.id)".data(using: .utf8)!)
        print("server did open connection \(connection.id)")
    }

    private func connectionDidStop(_ connection: ServerConnection) {
        self.connectionsByID.removeValue(forKey: connection.id)
        print("server did close connection \(connection.id)")
    }

    private func stop() {
        self.listener.stateUpdateHandler = nil
        self.listener.newConnectionHandler = nil
        self.listener.cancel()
        for connection in self.connectionsByID.values {
            connection.didStopCallback = nil
            connection.stop()
        }
        self.connectionsByID.removeAll()
    }
}


class ServerConnection {
    //The TCP maximum package size is 64K 65536
    let MTU = 65536

    private static var nextID: Int = 0
    let  connection: NWConnection
    let id: Int

    var zoneHandler: ((String, String) -> Void)?


    init(nwConnection: NWConnection) {
        connection = nwConnection
        id = ServerConnection.nextID
        ServerConnection.nextID += 1
    }

    var didStopCallback: ((Error?) -> Void)? = nil

    func start() {
        print("connection \(id) will start")
        connection.stateUpdateHandler = self.stateDidChange(to:)
        setupReceive()
        connection.start(queue: .main)
    }

    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .waiting(let error):
            connectionDidFail(error: error)
        case .ready:
            print("connection \(id) ready")
        case .failed(let error):
            connectionDidFail(error: error)
        default:
            break
        }
    }

    var block: Data = Data()

    private func setupReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: MTU) { (data, _, isComplete, error) in
            if let data = data, !data.isEmpty {
                if self.block.isEmpty {
                    self.block = data
                } else {
                    self.block.append(data)
                }

                let response = "HTTP/1.1 200 OK\r\n\r\n"
                let data = response.data(using: .utf8)!

                self.send(data: data)
            }
            if isComplete {
                let message = String(decoding: self.block, as: UTF8.self)
                print("connection \(self.id) did receive, data: \(self.block as NSData) string: \(message ?? "-")")

                let header = message.components(separatedBy: "\r\n\r\n")
    //            print(c)
    //            XMLParserSonos().parseRendererControl(xml: c[1])

                let endpoint = self.connection.currentPath?.remoteEndpoint?.debugDescription.components(separatedBy: ":")
                if endpoint?.count ?? 0 > 1, header.count > 1 {
                    self.zoneHandler?(endpoint?[0] ?? "", header[1])
                }
                self.connectionDidEnd()
            } else if let error = error {
                self.connectionDidFail(error: error)
            } else {
                self.setupReceive()
            }
        }
    }


    func send(data: Data) {
        self.connection.send(content: data, completion: .contentProcessed( { error in
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
            print("connection \(self.id) did send, data: \(data as NSData)")
        }))
    }

    func stop() {
        print("connection \(id) will stop")
    }



    private func connectionDidFail(error: Error) {
        print("connection \(id) did fail, error: \(error)")
        stop(error: error)
    }

    private func connectionDidEnd() {
        print("connection \(id) did end")
        stop(error: nil)
    }

    private func stop(error: Error?) {
        connection.stateUpdateHandler = nil
        connection.cancel()
        if let didStopCallback = didStopCallback {
            self.didStopCallback = nil
            didStopCallback(error)
        }
    }
}
