//
//  Fox.swift
//  Listener
//
//  Created by Nick Hayward on 1/4/25.
//

import FlyingFox
import Foundation
#if canImport(UIKit)
import UIKit
#endif
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
        #if !targetEnvironment(macCatalyst) && os(iOS) && canImport(UIKit)
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

                let xmlString = String(decoding: data, as: UTF8.self)

                // Parse ZoneGroupState
                guard let zoneGroupState = ZoneGroupLiteParser.parse(xmlString: xmlString) else {
                    // Most NOTIFY events from Sonos aren't ZoneGroupState
                    // (playback, volume, queue, etc.) — staying silent for
                    // those. Only warn when something that *looks* like a
                    // ZoneGroupState event fails to parse, so real
                    // regressions still surface.
                    if xmlString.contains("<ZoneGroupState") {
                        print("⚠️ NOTIFY looked like ZoneGroupState but ZoneGroupLiteParser returned nil (\(data.count) bytes)")
                    }
                    return HTTPResponse(statusCode: .ok)
                }
                print("📨 NOTIFY ZoneGroupState received (\(data.count) bytes)")
                self.onZoneGroupUpdate?(zoneGroupState)

                guard let services = ThirdPartyMediaServerDecrypter().handleItem(
                    householdID: zoneGroupState.houseHoldData,
                    encodedInput: zoneGroupState.thirdPartyMediaServers
                ) else {
                    // Log the readable ID, not the raw `houseHoldData` (a
                    // `Data` blob used by the decrypter that previously
                    // printed as "32 bytes").
                    print("⚠️ ThirdPartyMediaServerDecrypter returned nil for household \(zoneGroupState.houseHoldID)")
                    return HTTPResponse(statusCode: .ok)
                }

                let servers = MediaServerParser.parse(xmlString: services)
                // Cache the media servers
                KeychainManager.shared.saveMediaServers(householdId: zoneGroupState.houseHoldID, servers: servers)
                // The speaker hands over each service's current token here.
                // Requests read them from memory from now on; before this they
                // kept the token first read at launch and failed once it
                // expired, until the app was relaunched.
                KeychainTokenRefreshHandler.shared.mediaServersSaved(householdId: zoneGroupState.houseHoldID, servers: servers)
                // Plex belongs to Cue, not to a Sonos household: only borrow
                // the household's Plex sign-in when Cue has none of its own.
                // Overwriting it meant switching Sonos systems swapped in
                // another account's token (or one plex.tv rejects, which
                // resets the sign-in and the chosen server).
                if let plex = servers.first(where: { $0.type == .plex }),
                   !plex.token.isEmpty,
                   UserDefaults.standard.string(forKey: "com.cue.plexToken") == nil {
                    UserDefaults.standard.setValue(plex.token, forKey: "com.cue.plexToken")
                }
                print("📦 Cached \(servers.count) media servers for household: \(zoneGroupState.houseHoldID)")
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

