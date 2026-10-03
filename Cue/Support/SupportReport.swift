import CoreTransferable
import MusicSearchKit
import SonosKit
import SubscriptionKit
import SwiftUI
import UniformTypeIdentifiers

/// What a problem report says about the app and the device, above the log.
/// Built on the main actor: it reads the services' state as it is now.
@MainActor
enum SupportReport {
    static let email = "hi@cue.dance"

    /// `2026.6 (412)`.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var distribution: String {
        #if DEBUG
        return "Debug"
        #else
        return UIApplication.shared.isRunningInTestFlightEnvironment() ? "TestFlight" : "App Store"
        #endif
    }

    /// `iOS 27.0`, or the Mac's own version under Mac Catalyst, where
    /// `UIDevice` reports the iPadOS it imitates.
    static var system: String {
        #if targetEnvironment(macCatalyst)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #endif
    }

    /// The model identifier, `iPhone17,1` or `Mac14,2`: the marketing name
    /// hides which of a year's models it is.
    static var deviceModel: String {
        #if targetEnvironment(simulator)
        return (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Unknown") + " Simulator"
        #elseif targetEnvironment(macCatalyst)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #else
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        #endif
    }

    /// One line naming the build and the device: each launch's banner in the
    /// log, and the foot of the email.
    static var summary: String {
        "Cue \(appVersion) · \(distribution) · \(system) · \(deviceModel)"
    }

    /// The top of the attached file: when it was made, and the state of
    /// everything a log line can't say by itself.
    static func header() -> String {
        let now = Date.now
        let sonos = SonosService.shared
        let route = PlaybackRoute.shared
        let offline = OfflineMode.shared
        let store = LogStore.shared
        let services = MediaSearchService.supported
            .filter { CoreFeatures.shared.isEnabled($0) }
            .map(\.title)

        let sonosLine: String
        if sonos.isEnabled {
            sonosLine = "On, \(sonos.groups.count) groups, \(sonos.rooms.count) speakers"
        } else {
            sonosLine = "Off"
        }

        let detailed: String
        if store.isDetailed, let until = store.detailedUntil {
            detailed = "On until \(until.formatted(date: .abbreviated, time: .shortened))"
        } else {
            #if DEBUG
            detailed = "Debug build, always on"
            #else
            detailed = "Off"
            #endif
        }

        var offlineLine = offline.isOn ? "On" : "Off"
        if !offline.hasNetwork {
            offlineLine += ", no network"
        }

        let lines = [
            "Cue Problem Report",
            "Made: \(now.formatted(date: .complete, time: .standard)) (\(TimeZone.current.identifier))",
            "App: Cue \(appVersion), \(distribution)",
            "Device: \(deviceModel), \(system), \(Locale.current.identifier)",
            "ID: \(SubscriptionService.shared.userID)",
            "Cue Super: \(SubscriptionService.shared.subscription.isActive ? "Yes" : "No")",
            "Playing on: \(route.group?.nameWithCount ?? "This device")",
            "Sonos: \(sonosLine)",
            "Services: \(services.isEmpty ? "None" : services.joined(separator: ", "))",
            "Offline Mode: \(offlineLine)",
            "Detailed Logging: \(detailed)",
            "",
            "Times below are the device's own (\(TimeZone.current.identifier)). Newest lines are at the bottom.",
            String(repeating: "─", count: 60),
        ]
        return lines.joined(separator: "\n")
    }

    /// The email's body: room to describe the problem, and the facts support
    /// would otherwise have to ask for.
    static func emailBody() -> String {
        """



        ——
        Please describe what happened above: what you did, what you expected, and roughly when. Cue's log from the last few days is attached, with passwords and sign-in tokens left out.

        \(summary)
        ID: \(SubscriptionService.shared.userID)
        """
    }

    static var emailSubject: String {
        "Cue Problem Report (\(appVersion))"
    }

    /// Writes the report — header and log — to a file to attach or share.
    /// The log is read off the main thread.
    static func makeFile() async throws -> URL {
        let header = header()
        return try await Task.detached(priority: .userInitiated) {
            try LogStore.shared.exportFile(header: header)
        }.value
    }
}

/// The report as something to share: the file is made when it's shared,
/// so it has every line up to that moment.
struct SupportReportFile: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in
            SentTransferredFile(try await SupportReport.makeFile())
        }
    }
}
