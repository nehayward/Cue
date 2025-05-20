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
#if !os(watchOS)
        setupLifecycleObservers()
#endif
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
//        print("UPnPSubscriber: App entering foreground")
//        isActive = true
//        
//        // Wait for server to be ready before resubscribing
////        SonosListener.shared.onServerReady = { [weak self] in
//            // Request fresh subscriptions
//            Task { [weak self] in
//                guard let self else { return }
//                // Clear old subscriptions
//                await self.subscriptionManager.clearAllSIDs()
//                await self.sendSubscribeRequests()
//                // Start renewal timer
//                self.startRenewalTimer()
//            }
////        }
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
        guard let localIP = IPActive().getIPAddress() else {
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
        guard let localIP = IPActive().getIPAddress() else {
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
        guard let localIP = IPActive().getIPAddress() else {
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
        guard let localIP = IPActive().getIPAddress() else {
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
        guard let localIP = IPActive().getIPAddress() else {
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
