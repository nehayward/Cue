import Foundation
import Observation

@Observable
final class RemoteFeatureFlags {
    static let shared = RemoteFeatureFlags()

    enum Flag: String, CaseIterable {
        case lastFM
        /// Live Transcription in the player — and the station relay it
        /// plays through. On in debug builds; in release, off until the
        /// flags endpoint turns it on.
        case liveTranscription
    }

    private let url = URL(string: "https://api.cue.dance/flags")!
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    #if DEBUG
    private var enabled: Set<Flag> = Set(Flag.allCases)
    #else
    private var enabled: Set<Flag> = []
    #endif

    func isEnabled(_ flag: Flag) -> Bool {
        enabled.contains(flag)
    }

    func fetch() {
        #if DEBUG
        return
        #endif
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let flags = try? JSONDecoder().decode([String: RemoteFlag].self, from: data) else { return }
            await apply(flags)
        }
    }

    @MainActor
    private func apply(_ flags: [String: RemoteFlag]) {
        for (key, flag) in flags {
            guard let f = Flag(rawValue: key) else { continue }
            if evaluate(flag) { enabled.insert(f) } else { enabled.remove(f) }
        }
    }

    private func evaluate(_ flag: RemoteFlag) -> Bool {
        guard flag.enabled else { return false }
        guard let min = flag.minVersion else { return true }
        return appVersion.compare(min, options: .numeric) != .orderedAscending
    }
}

private struct RemoteFlag: Decodable {
    let enabled: Bool
    let minVersion: String?
}
