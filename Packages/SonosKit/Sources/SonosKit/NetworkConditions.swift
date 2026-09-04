import Foundation
import Network

/// A one-shot look at the network, for work that should wait for Wi‑Fi.
public enum NetworkConditions {
    /// True on a connection that is up and neither expensive (cellular, a
    /// personal hotspot) nor constrained (Low Data Mode).
    public static func isUnmetered() async -> Bool {
        let path = await currentPath()
        return path.status == .satisfied && !path.isExpensive && !path.isConstrained
    }

    public static func currentPath() async -> NWPath {
        let monitor = NWPathMonitor()
        let once = OnceFlag()
        return await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                guard once.trySet() else { return }
                monitor.cancel()
                continuation.resume(returning: path)
            }
            monitor.start(queue: .global(qos: .utility))
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    /// True the first time only.
    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isSet { return false }
        isSet = true
        return true
    }
}
