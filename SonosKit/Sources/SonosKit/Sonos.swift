//import Foundation
//import Observation
//
//
//actor Searcher {
//    enum BluetoothLEScanError: Error {
//        case bluetoothNotAvailable
//    }
//
//
//    private let bluetoothLEDelegate: SonosDeviceDiscoveryServiceDelegate = SonosDeviceDiscoveryServiceDelegate()
//    private var activeTask: Task<Room, Error>?
//
//    func getFirstRoom() async throws -> Room {
//        if let existingTask = activeTask {
//            return try await existingTask.value
//        }
//
//        let task = Task<Room, Error> {
//            guard bluetoothLEDelegate.bluetoothIsOn else {
//                activeTask = nil
//                throw BluetoothLEScanError.bluetoothNotAvailable
//            }
//
//            self.bluetoothLEDelegate.central.scanForPeripherals(withServices: nil)
//
//            try await Task.sleep(nanoseconds: (UInt64(5) * 1_000_000_000))
//
//            let devices = bluetoothLEDelegate.foundPeripheral.compactMap { BluetoothLEDevice(peripheral: $0) }
//
//            bluetoothLEDelegate.central.stopScan()
//            bluetoothLEDelegate.foundPeripheral = []
//
//            activeTask = nil
//
//            return devices
//        }
//
//        activeTask = task
//
//        return try await task.value
//
//    }
//}
//
//final class SonosDeviceDiscoveryServiceDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
//    var room: Room? = nil
//
//    private let serviceType = "_sonos._tcp"
//    private var services = [NetService]()
//    private let browser = NetServiceBrowser()
//
//    private var roomContinuation: CheckedContinuation<Room, Never>? = nil
//
//    func discover() {
//        browser.delegate = self
//        browser.searchForServices(ofType: serviceType, inDomain: "")
//    }
//
//    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
//        print("Found service: \(service.name)")
//
//        services.append(service)
//        service.delegate = self
//        service.resolve(withTimeout: 5)
//        browser.stop()
//    }
//
//    func netServiceDidResolveAddress(_ sender: NetService) {
//        print("Resolved service: \(sender.name) at \(sender.addresses!)")
//        if let txtRecordData = sender.txtRecordData() {
//            let txtRecord = NetService.dictionary(fromTXTRecord: txtRecordData)
//
//            guard let locationData = txtRecord["location"],
//                    let location = String(data: locationData, encoding: .utf8) else {
//                return
//            }
//
//            print(location)
//
//            let components = URLComponents(string: location)
//            guard let ip = components?.host else {
//                return
//            }
//
//            let room = Room(id: sender.name, ip: ip, name: sender.name)
//            self.room = room
//        }
//
//        if !sender.isEqual(services.last) {
//            sender.stop()
//        } else {
//            print("Stopped discovering Sonos devices")
//            print("Finished discovering Sonos devices")
//            browser.stop()
//        }
//    }
//
//    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
//        print("Failed to resolve service: \(sender.name), error: \(errorDict)")
//    }
//}
