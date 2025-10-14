//
//  Fox.swift
//  Listener
//
//  Created by Nick Hayward on 1/4/25.
//

import FlyingFox
import Foundation
import UIKit
import Network


final class MediaServerHandler {
    static var shared = MediaServerHandler()
    var eventHandler: ((String) -> Void)?
    var onServerListening: ((String) async -> Void)?
    var onZoneGroupUpdate: ((ZoneGroupLiteParser.ZoneGroupState) -> Void)?
    var deviceIP: String = ""
    var port: Int
    
    private let server: HTTPServer
    private var serverTask: Task<Void, Error>?
    private let ipDetector = IPActive()
    
    init() {
        #if targetEnvironment(macCatalyst)
        let port: UInt16 = 1603
        #else
        let port: UInt16 = 1604
        #endif
        
        self.port = Int(port)
        // Initialize server with a specific address to ensure we get a proper listening address
        server = HTTPServer(port: port)
//        setupNotificationObservers()
        getLocalIPAddress()
        //        KeychainManager.shared.clearMediaServers(householdId: "Sonos_GBw44sBd7swQ55xlbUSTzNmTlp")
    }
    
    private func getLocalIPAddress() {
        if let ip = ipDetector.getIPAddress() {
            deviceIP = ip
            print("📱 Device IP: \(ip)")
        } else {
            print("❌ Failed to get device IP address")
        }
    }
    
    private func setupNotificationObservers() {
        #if !targetEnvironment(macCatalyst) && os(iOS)
        // Mac Catalyst uses iOS APIs
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }
    @objc private func appDidEnterBackground() {
        print("App entered background - stopping server")
        stop()
    }
    
    @objc private func appWillEnterForeground() {
        print("App entered foreground - starting server")
//        start()
    }
    
    func start() async {
        if await server.isListening {
            return
        }
        // Stop any existing server task
        stop()
        
        print("Starting server...")
        
        Task {
            await server.appendRoute("NOTIFY /") { [weak self] request in
                guard let self = self else { return HTTPResponse(statusCode: .internalServerError) }
                let data = try await request.bodyData
                
//                let rinconID: String?
//                if let SID = request.headers[.init(rawValue: "SID")], let rinconRange = SID.range(of: "RINCON_[A-Z0-9]{16}", options: .regularExpression) {
//                    rinconID = String(SID[rinconRange])
//                }
//                
                let xmlString = String(decoding: data, as: UTF8.self)
            
                // Parse ZoneGroupState
                if let zoneGroupState = ZoneGroupLiteParser.parse(xmlString: xmlString) {
                    self.onZoneGroupUpdate?(zoneGroupState)
                    let services = ThirdPartyMediaServerDecrypter().handleItem(householdID: zoneGroupState.houseHoldData, encodedInput: zoneGroupState.thirdPartyMediaServers)
                    if let services = services {
                        let servers = MediaServerParser.parse(xmlString: services)
                        // Cache the media servers
                        KeychainManager.shared.saveMediaServers(householdId: zoneGroupState.houseHoldID, servers: servers)
                        // MARK: Update move to Keychain Manger with in Memory that can be access from MusicSearchKit and SonosKit
                        if let plex = servers.first(where: { $0.type == .plex }) {
                            let token = plex.token
                            UserDefaults.standard.setValue(token, forKey: "com.clic.plexToken")
                        }
                        print("📦 Cached \(servers.count) media servers for household: \(zoneGroupState.houseHoldData)")
                    }
                }
                return HTTPResponse(statusCode: .ok)
            }
        }
        
        serverTask = Task {
            do {
                // Set up the route directly on the server
                // Start the server
                try await server.run()
            } catch {
                print("❌ Server error: \(error)")
                throw error
            }
        }
        Task {
            do {
                try await server.waitUntilListening()
                print(await server.listeningAddress)
                if let ip = ipDetector.getIPAddress() {
                    print("✅ Server started successfully!")
                    print("📡 Listening on: \(ip)")
                    deviceIP = ip
                    await onServerListening?(ip)
                }
            } catch {
                print("Failed to get listening address")
                throw error
            }
        }
    }
    
    func stop() {
        print("Stopping server...")
        serverTask?.cancel()
        serverTask = nil
        print("Server stopped")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }
}

