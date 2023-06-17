import Foundation

final class SonosDeviceDiscoveryService: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, ObservableObject {
    private let serviceType = "_sonos._tcp"
    private var services = [NetService]()
    private let browser = NetServiceBrowser()

    @Published var devices = [SonosDevice]()
    @Published var discoveredDevice: SonosDevice?

    private var deviceContinuation: CheckedContinuation<[SonosDevice], Never>?

    func discover() {
        browser.delegate = self
        browser.searchForServices(ofType: serviceType, inDomain: "")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("Found service: \(service.name)")
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        print("Resolved service: \(sender.name) at \(sender.addresses!)")

        // Extract the IP address from the resolved addresses
        if let address = sender.addresses?.first {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(address.count)
            let sockaddrPtr = address.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: sockaddr.self) }
            if getnameinfo(sockaddrPtr, len, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ipAddress = String(cString: hostname)
                let device = SonosDevice(name: sender.name, ipAddress: ipAddress)
//                if sender.name.contains("Garage") {
//                    discoveredDevice = device
//                    devices.append(device)
//                }

                    discoveredDevice = device
                    devices.append(device)
                
                
                print("Found Sonos device: \(device.name) at IP address \(device.ipAddress)")
            }
        }

        if !sender.isEqual(services.last) {
            sender.stop()
        } else {
            print("Stopped discovering Sonos devices")
            print("Finished discovering Sonos devices")
            browser.stop()
            deviceContinuation?.resume(returning: devices)
            deviceContinuation = nil
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {

    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("Failed to resolve service: \(sender.name), error: \(errorDict)")
    }

    @MainActor
    func getDevices() async -> [SonosDevice] {
        return await withCheckedContinuation { continuation in
            discover()
            deviceContinuation = continuation

//            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
//                self.deviceContinuation?.resume(returning: [])
//                self.deviceContinuation = nil
//            }
        }
    }
}
