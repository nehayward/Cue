import Foundation

extension SonosAPI {
    func subscribeToSonos(port: Int, deviceIP: String, sonosIP: String) async throws {
        guard !deviceIP.isEmpty else {
            print("❌ Cannot subscribe: Device IP not available")
            throw NSError(domain: "MediaServerHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Device IP not available"])
        }

        try await TopologyEventSubscription.shared.subscribeIfNeeded(
            session: session,
            port: port,
            deviceIP: deviceIP,
            sonosIP: sonosIP
        )
    }

    func getDeviceID(IP: String) async -> String? {
        let arguments: OrderedKeys = [
            ("VariableName", "R_TrialZPSerial")
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: IP, action: "GetString", arguments: arguments, endpoint: "SystemProperties") else {
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        if let deviceID = try? xmlParser.parseValue(xml: xml, named: "StringValue") {
            return deviceID
        }
        return nil
    }

}

/// Tracks the single ZoneGroupTopology event subscription. `onServerListening()`
/// runs on foreground activation *and* on every topology refresh; before this,
/// each call issued a fresh SUBSCRIBE, so the speaker accumulated parallel
/// subscriptions and delivered every ZoneGroupState NOTIFY once per SID.
/// Now concurrent callers coalesce into one request, a live subscription is
/// renewed (SUBSCRIBE with the stored SID) instead of duplicated, and a
/// background task renews before the speaker's timeout lapses.
private actor TopologyEventSubscription {
    static let shared = TopologyEventSubscription()

    private var sid: String?
    private var expiresAt: Date = .distantPast
    private var subscribedIP: String?
    private var subscribedCallback: String?
    private var inFlight: Task<Void, Error>?
    private var renewalTask: Task<Void, Never>?

    private let requestedTimeout: TimeInterval = 500

    func subscribeIfNeeded(session: URLSession, port: Int, deviceIP: String, sonosIP: String) async throws {
        if let inFlight {
            try await inFlight.value
            return
        }

        let task = Task {
            try await self.subscribe(session: session, port: port, deviceIP: deviceIP, sonosIP: sonosIP)
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    private func subscribe(session: URLSession, port: Int, deviceIP: String, sonosIP: String) async throws {
        let callback = "<http://\(deviceIP):\(port)>"

        // Renew while the speaker still knows our SID; a renewal keeps the
        // existing callback registration instead of adding a second one. A
        // changed callback (device moved networks) needs a fresh
        // subscription — renewals can't update it.
        if let sid, subscribedIP == sonosIP, subscribedCallback == callback, Date.now < expiresAt {
            do {
                let timeout = try await send(session: session, sonosIP: sonosIP, headers: [
                    "SID": sid,
                    "TIMEOUT": "Second-\(Int(requestedTimeout))",
                ]).timeout
                expiresAt = Date.now.addingTimeInterval(timeout)
                scheduleRenewal(session: session, port: port, deviceIP: deviceIP, sonosIP: sonosIP, after: timeout)
                return
            } catch {
                // Speaker rebooted or dropped the SID (412) — fall through to
                // a fresh subscription.
                self.sid = nil
            }
        }

        let response = try await send(session: session, sonosIP: sonosIP, headers: [
            "CALLBACK": callback,
            "NT": "upnp:event",
            "TIMEOUT": "Second-\(Int(requestedTimeout))",
        ])
        sid = response.sid
        subscribedIP = sonosIP
        subscribedCallback = callback
        expiresAt = Date.now.addingTimeInterval(response.timeout)
        print("✅ Subscribed to Sonos topology events. SID: \(response.sid ?? "-"), timeout: \(Int(response.timeout))s")
        scheduleRenewal(session: session, port: port, deviceIP: deviceIP, sonosIP: sonosIP, after: response.timeout)
    }

    /// Renew at ~80% of the granted timeout so the subscription never lapses
    /// while the app is foregrounded. Replaced on every (re)subscribe; a
    /// failed renewal clears state so the next `subscribeIfNeeded` starts
    /// fresh.
    private func scheduleRenewal(session: URLSession, port: Int, deviceIP: String, sonosIP: String, after timeout: TimeInterval) {
        renewalTask?.cancel()
        renewalTask = Task {
            try? await Task.sleep(for: .seconds(timeout * 0.8))
            guard !Task.isCancelled else { return }
            do {
                try await self.subscribe(session: session, port: port, deviceIP: deviceIP, sonosIP: sonosIP)
            } catch {
                self.sid = nil
                self.expiresAt = .distantPast
            }
        }
    }

    private func send(session: URLSession, sonosIP: String, headers: [String: String]) async throws -> (sid: String?, timeout: TimeInterval) {
        let url = URL(string: "http://\(sonosIP):1400/ZoneGroupTopology/Event")!
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "MediaServerHandler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "MediaServerHandler", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Subscription failed with status code: \(httpResponse.statusCode)"])
        }

        let sid = httpResponse.allHeaderFields["SID"] as? String
        // "Second-500" → 500. Fall back to the requested timeout.
        var timeout = requestedTimeout
        if let raw = httpResponse.allHeaderFields["TIMEOUT"] as? String,
           let seconds = TimeInterval(raw.replacingOccurrences(of: "Second-", with: "")) {
            timeout = seconds
        }
        return (sid, timeout)
    }
}
