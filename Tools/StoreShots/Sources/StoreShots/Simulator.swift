import Foundation

/// The simulators, through `xcrun simctl`.
struct Simulator {
    let udid: String
    let name: String
    /// `iOS`, `watchOS`, `tvOS`, `xrOS`.
    let platform: String

    static func named(_ name: String) throws -> Simulator {
        let data = try Shell.output("xcrun", "simctl", "list", "devices", "available", "-j")
        struct List: Decodable {
            struct Device: Decodable { let udid: String; let name: String; let state: String }
            let devices: [String: [Device]]
        }
        let list = try JSONDecoder().decode(List.self, from: data)
        for (runtime, devices) in list.devices.sorted(by: { $0.key > $1.key }) {
            guard let device = devices.first(where: { $0.name == name }) else { continue }
            let platform = ["watchOS", "tvOS", "xrOS", "iOS"].first { runtime.contains($0) } ?? "iOS"
            let simulator = Simulator(udid: device.udid, name: name, platform: platform)
            if device.state != "Booted" {
                print("booting \(name)")
                try Shell.run("xcrun", "simctl", "boot", device.udid)
                Thread.sleep(forTimeInterval: 8)
            }
            return simulator
        }
        throw Failure("no available simulator named \(name)")
    }

    /// 9:41, full battery and signal, as in Apple's own screenshots. Only iOS
    /// and iPadOS simulators take an override.
    func overrideStatusBar() throws {
        guard platform == "iOS" else { return }
        try Shell.run("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41",
                      "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                      "--cellularMode", "active", "--cellularBars", "4",
                      "--batteryState", "charged", "--batteryLevel", "100")
    }

    func relaunch(_ bundleID: String, arguments: [String]) throws {
        _ = try? Shell.run("xcrun", "simctl", "terminate", udid, bundleID, quiet: true)
        Thread.sleep(forTimeInterval: 1)
        try Shell.run(["xcrun", "simctl", "launch", udid, bundleID] + arguments, quiet: true)
    }

    func screenshot(to url: URL, display: String?) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var arguments = ["xcrun", "simctl", "io", udid, "screenshot", "--type=png"]
        if let display { arguments.append("--display=\(display)") }
        arguments.append(url.path)
        try Shell.run(arguments, quiet: true)
    }

    /// Records the screen for `seconds`, as H.264, the codec the previews read fastest.
    func record(to url: URL, seconds: Double, display: String?) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var arguments = ["simctl", "io", udid, "recordVideo", "--codec=h264", "--force"]
        if let display { arguments.append("--display=\(display)") }
        arguments.append(url.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        print("recording \(name) for \(Int(seconds)) s → \(url.lastPathComponent)")
        Thread.sleep(forTimeInterval: seconds)
        process.interrupt()
        process.waitUntilExit()
    }
}

enum Shell {
    @discardableResult
    static func run(_ arguments: String..., quiet: Bool = false) throws -> Int32 {
        try run(arguments, quiet: quiet)
    }

    @discardableResult
    static func run(_ arguments: [String], quiet: Bool = false) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if quiet {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure("\(arguments.joined(separator: " ")) failed (\(process.terminationStatus))")
        }
        return process.terminationStatus
    }

    static func output(_ arguments: String...) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}
