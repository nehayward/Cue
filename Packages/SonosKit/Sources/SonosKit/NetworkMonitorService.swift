import Observation
import Network

@Observable
public class NetworkMonitorService {
    private let networkMonitor = NWPathMonitor(prohibitedInterfaceTypes: [.cellular])
    private let workerQueue = DispatchQueue(label: "Monitor")
    public var isConnected = false

    public init() {
        networkMonitor.pathUpdateHandler = { path in
            self.isConnected = path.status == .satisfied
        }
        networkMonitor.start(queue: workerQueue)
    }
}
