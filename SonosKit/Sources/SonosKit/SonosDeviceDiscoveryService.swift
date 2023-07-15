import Foundation
import Observation

#if os(iOS)
@Observable
final class SonosDeviceDiscoveryService: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var room: Room? = nil

    private let serviceType = "_sonos._tcp"
    private var services = [NetService]()
    private let browser = NetServiceBrowser()

    private var roomContinuation: CheckedContinuation<Room, Never>? = nil

    func discover() {
        browser.delegate = self
        browser.searchForServices(ofType: serviceType, inDomain: "")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("Found service: \(service.name)")

        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
        browser.stop()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        print("Resolved service: \(sender.name) at \(sender.addresses!)")
        if let txtRecordData = sender.txtRecordData() {
            let txtRecord = NetService.dictionary(fromTXTRecord: txtRecordData)

            guard let locationData = txtRecord["location"],
                    let location = String(data: locationData, encoding: .utf8) else {
                return
            }

            print(location)

            let components = URLComponents(string: location)
            guard let ip = components?.host else {
                return
            }

            let room = Room(id: sender.name, ip: ip, name: sender.name)
            self.room = room
            roomContinuation?.resume(with: .success(room))
            roomContinuation = nil
        }


//        if let address = sender.addresses?.first {
//            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
//            let len = socklen_t(address.count)
//            let sockaddrPtr = address.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: sockaddr.self) }
//            if getnameinfo(sockaddrPtr, len, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
//                let ipAddress = String(cString: hostname)
//                let device = Room(id: sender.name, ip: ipAddress, name: sender.name)
//                    room = device
//                
//
////                print("Found Sonos device: \(device.name) at IP address \(device.ipAddress)")
//            }
//        }

        if !sender.isEqual(services.last) {
            sender.stop()
        } else {
            print("Stopped discovering Sonos devices")
            print("Finished discovering Sonos devices")
            browser.stop()
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {

    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("Failed to resolve service: \(sender.name), error: \(errorDict)")
    }

//    @MainActor
//    func getDevices() async -> [Room] {
//        return await withCheckedContinuation { continuation in
//            discover()
//            deviceContinuation = continuation
//        }
//    }

    @MainActor
    func getFirstRoom() async -> Room {
        return await withCheckedContinuation { continuation in
            discover()
            roomContinuation = continuation
        }
    }
}

#endif
