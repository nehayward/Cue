//
//  if.swift
//  Listener
//
//  Created by Nick Hayward on 1/3/25.
//

import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class SonosSubscriberService {
    static var shared = SonosSubscriberService(callbackPort: 56002)
    // Configuration
    private let callbackPort: UInt16
    
    private let devicePort = "1400"
    private var deviceIPs: [String] = []
    private var renewalTimer: Timer?
    private let renewalInterval: TimeInterval
    
    // Remove queue, keep actor
    private let subscriptionManager = SubscriptionManager()
    private var isActive = true
    
    init(callbackPort: UInt16, renewalInterval: TimeInterval = 60 * 30) {
        self.callbackPort = callbackPort
        self.renewalInterval = renewalInterval
        setupLifecycleObservers()
    }
    
    deinit {
        removeLifecycleObservers()
        stopRenewalTimer()
        Task {
            // Removed unsubscribeAll() call
        }
    }
    
    // Add or update device IPs
    func updateDevices(_ ips: [String]) {
        if ips != deviceIPs {
            self.deviceIPs = ips
            Task {
                await self.subscriptionManager.clearAllSIDs()
                await self.sendSubscribeRequests()
            }
        }
    }
    
    func subscribe() {
        Task {
            await self.subscriptionManager.clearAllSIDs()
            await self.sendSubscribeRequests()
        }
    }
    
    // Timer management
    private func startRenewalTimer() {
        print("------- Will Renew in \(renewalInterval)")
        stopRenewalTimer() // Make sure we stop any existing timer first
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.renewalTimer = Timer.scheduledTimer(
                timeInterval: self.renewalInterval,
                target: self,
                selector: #selector(self.renewalTimerFired),
                userInfo: nil,
                repeats: true
            )
            if let timer = self.renewalTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    @objc private func renewalTimerFired() {
        Task { [weak self] in
            print("------- Renewing --------")
            await self?.sendSubscribeRequests()
        }
    }
    
    private func stopRenewalTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.renewalTimer?.invalidate()
            self?.renewalTimer = nil
        }
    }
    
//    private func restartRenewalTimer() {
//        stopRenewalTimer()
//        startRenewalTimer()
//    }
    
    // Add lifecycle management
    private func setupLifecycleObservers() {
#if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
#elseif os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackground),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
#endif
    }
    
    private func removeLifecycleObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    @objc private func handleBackground() {
        print("UPnPSubscriber: App entering background")
        isActive = false
        stopRenewalTimer()
        Task {
            await subscriptionManager.clearAllSIDs()
        }
    }
    
    @objc private func handleForeground() {
        print("UPnPSubscriber: App entering foreground")
        isActive = true
        
        // Wait for server to be ready before resubscribing
//        SonosListener.shared.onServerReady = { [weak self] in
            // Request fresh subscriptions
            Task { [weak self] in
                guard let self else { return }
                // Clear old subscriptions
                await self.subscriptionManager.clearAllSIDs()
                await self.sendSubscribeRequests()
                // Start renewal timer
                self.startRenewalTimer()
            }
//        }
    }
    
    func getGroups() async {
        guard let deviceIP = deviceIPs.first else {
            print("Failed")
            return
        }
        
        await processSubscription(
            createZoneGroupTopologySubscribeRequest(forIP: deviceIP),
            deviceIP: deviceIP,
            serviceType: "zgt"
        )
    }
    
    func sendSubscribeRequests() async {
        startRenewalTimer()
        for deviceIP in deviceIPs {
            await processSubscription(
                createAVTransportSubscribeRequest(forIP: deviceIP),
                deviceIP: deviceIP,
                serviceType: "avt"
            )

            await processSubscription(
                createGroupRenderingControlSubscribeRequest(forIP: deviceIP),
                deviceIP: deviceIP,
                serviceType: "grc"
            )

            await processSubscription(
                createRenderingControlSubscribeRequest(forIP: deviceIP),
                deviceIP: deviceIP,
                serviceType: "rc"
            )
            
            await processSubscription(
                createDevicePropertiesSubscribeRequest(forIP: deviceIP),
                deviceIP: deviceIP,
                serviceType: "dp"
            )
        }
    }

    private func processSubscription(_ request: URLRequest?, deviceIP: String, serviceType: String) async {
        guard let request = request else {
            print("\(serviceType.uppercased()) request creation failed for \(deviceIP)")
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("\(serviceType.uppercased()) subscribe response for \(deviceIP): \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200,
                   let sid = httpResponse.allHeaderFields["SID"] as? String {
                    await subscriptionManager.storeSID(sid, forDevice: "\(deviceIP)_\(serviceType)")
                    print("Stored \(serviceType.uppercased()) SID for \(deviceIP): \(sid)")
                }
            }
        } catch {
            print("\(serviceType.uppercased()) subscribe failed for \(deviceIP): \(error)")
        }
    }

    // Create AVTransport subscribe request
    private func createAVTransportSubscribeRequest(forIP deviceIP: String) -> URLRequest? {
        // Get the local IP address for callback
        guard let localIP = try? IP.getInterfaceIPAddress(interfaceName: "en0") else {
            print("Failed to get local IP address")
            return nil
        }
        
        print(localIP)
        
        let urlString = "http://\(deviceIP):\(devicePort)/MediaRenderer/AVTransport/Event"
        guard let url = URL(string: urlString) else {
            print("Invalid URL for device \(deviceIP)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.addValue("<http://\(localIP):\(callbackPort)>", forHTTPHeaderField: "CALLBACK")
        request.addValue("upnp:event", forHTTPHeaderField: "NT")
        request.addValue("Second-\(max(0, renewalInterval))", forHTTPHeaderField: "TIMEOUT")
        return request
    }

    // Create GroupRenderingControl subscribe request
    private func createGroupRenderingControlSubscribeRequest(forIP deviceIP: String) -> URLRequest? {
        guard let localIP = try? IP.getInterfaceIPAddress(interfaceName: "en0") else {
            print("Failed to get local IP address")
            return nil
        }
        
        let urlString = "http://\(deviceIP):\(devicePort)/MediaRenderer/GroupRenderingControl/Event"
        guard let url = URL(string: urlString) else {
            print("Invalid URL for device \(deviceIP)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.addValue("<http://\(localIP):\(callbackPort)>", forHTTPHeaderField: "CALLBACK")
        request.addValue("upnp:event", forHTTPHeaderField: "NT")
        request.addValue("Second-3600", forHTTPHeaderField: "TIMEOUT")
        return request
    }

    // Create RenderingControl subscribe request
    private func createRenderingControlSubscribeRequest(forIP deviceIP: String) -> URLRequest? {
        guard let localIP = try? IP.getInterfaceIPAddress(interfaceName: "en0") else {
            print("Failed to get local IP address")
            return nil
        }
        
        let urlString = "http://\(deviceIP):\(devicePort)/MediaRenderer/RenderingControl/Event"
        guard let url = URL(string: urlString) else {
            print("Invalid URL for device \(deviceIP)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.addValue("<http://\(localIP):\(callbackPort)>", forHTTPHeaderField: "CALLBACK")
        request.addValue("upnp:event", forHTTPHeaderField: "NT")
        request.addValue("Second-3600", forHTTPHeaderField: "TIMEOUT")
        return request
    }

    // Create ZoneGroupTopology subscribe request
    private func createZoneGroupTopologySubscribeRequest(forIP deviceIP: String) -> URLRequest? {
        guard let localIP = try? IP.getInterfaceIPAddress(interfaceName: "en0") else {
            print("Failed to get local IP address")
            return nil
        }
        
        let urlString = "http://\(deviceIP):\(devicePort)/ZoneGroupTopology/Event"
        guard let url = URL(string: urlString) else {
            print("Invalid URL for device \(deviceIP)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.addValue("<http://\(localIP):\(callbackPort)>", forHTTPHeaderField: "CALLBACK")
        request.addValue("upnp:event", forHTTPHeaderField: "NT")
        request.addValue("Second-3600", forHTTPHeaderField: "TIMEOUT")
        return request
    }

    // Create DeviceProperties subscribe request
    private func createDevicePropertiesSubscribeRequest(forIP deviceIP: String) -> URLRequest? {
        guard let localIP = try? IP.getInterfaceIPAddress(interfaceName: "en0") else {
            print("Failed to get local IP address")
            return nil
        }
        
        let urlString = "http://\(deviceIP):\(devicePort)/DeviceProperties/Event"
        guard let url = URL(string: urlString) else {
            print("Invalid URL for device \(deviceIP)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.addValue("<http://\(localIP):\(callbackPort)>", forHTTPHeaderField: "CALLBACK")
        request.addValue("upnp:event", forHTTPHeaderField: "NT")
        request.addValue("Second-3600", forHTTPHeaderField: "TIMEOUT")
        return request
    }
    
}

extension SonosSubscriberService {
    fileprivate actor SubscriptionManager {
        private var sids: [String: String] = [:]
        
        func storeSID(_ sid: String, forDevice deviceIP: String) {
            sids[deviceIP] = sid
        }
        
        func getSID(forDevice deviceIP: String) -> String? {
            return sids[deviceIP]
        }
        
        func removeSID(forDevice deviceIP: String) {
            sids.removeValue(forKey: deviceIP)
        }
        
        func clearAllSIDs() {
            sids.removeAll()
        }
        
        func getAllSIDs() -> [String: String] {
            return sids
        }
    }
}

class IP {
    private enum AddressRequestType {
        case ipAddress
        case netmask
    }
    
    // From BDS ioccom.h
    // Macro to create ioctl request
    private static func _IOC (_ io: UInt32, _ group: UInt32, _ num: UInt32, _ len: UInt32) -> UInt32 {
        let rv = io | (( len & UInt32(IOCPARM_MASK)) << 16) | ((group << 8) | num)
        return rv
    }
    
    // Macro to create read/write IOrequest
    private static func _IOWR (_ group: Character , _ num : UInt32, _ size: UInt32) -> UInt32 {
        return _IOC(IOC_INOUT, UInt32 (group.asciiValue!), num, size)
    }
    
    private static func _interfaceAddressForName (_ name: String, _ requestType: AddressRequestType) throws -> String {
        
        var ifr = ifreq ()
        ifr.ifr_ifru.ifru_addr.sa_family = sa_family_t(AF_INET)
        
        // Copy the name into a zero padded 16 CChar buffer
        
        let ifNameSize = Int (IFNAMSIZ)
        var b = [CChar] (repeating: 0, count: ifNameSize)
        strncpy (&b, name, ifNameSize)
        
        // Convert the buffer to a 16 CChar tuple - that's what ifreq needs
        ifr.ifr_name = (b [0], b [1], b [2], b [3], b [4], b [5], b [6], b [7], b [8], b [9], b [10], b [11], b [12], b [13], b [14], b [15])
        
        let ioRequest: UInt32 = {
            switch requestType {
            case .ipAddress: return _IOWR("i", 33, UInt32(MemoryLayout<ifreq>.size))    // Magic number SIOCGIFADDR - see sockio.h
            case .netmask: return _IOWR("i", 37, UInt32(MemoryLayout<ifreq>.size))      // Magic number SIOCGIFNETMASK
            }
        } ()
        
        if ioctl(socket(AF_INET, SOCK_DGRAM, 0), UInt(ioRequest), &ifr) < 0 {
            throw POSIXError (POSIXErrorCode (rawValue: errno) ?? POSIXErrorCode.EINVAL)
        }
        
        let sin = unsafeBitCast(ifr.ifr_ifru.ifru_addr, to: sockaddr_in.self)
        let rv = String (cString: inet_ntoa (sin.sin_addr))
        
        return rv
    }
    
    public static func getInterfaceIPAddress (interfaceName: String) throws -> String {
        return try _interfaceAddressForName(interfaceName, .ipAddress)
    }
    
    public static func getInterfaceNetMask (interfaceName: String) throws -> String {
        return try _interfaceAddressForName(interfaceName, .netmask)
    }
}
