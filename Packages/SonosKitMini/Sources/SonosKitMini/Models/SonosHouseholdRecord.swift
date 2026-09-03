import Foundation

/// Read-only view of the household records the main app publishes to iCloud under
/// `sonos_known_households`.
///
/// Duplicated rather than shared because SonosKitMini deliberately does not depend
/// on SonosKit — Cue Mini and the Watch link only this package. Only the fields
/// needed to reach a speaker are decoded, and every one but `id` tolerates being
/// absent so a newer writer cannot break an older reader.
///
/// Cue Mini never writes this key. The main app owns it, including deletions, and
/// a write from here would resurrect a household removed on another device.
struct SonosHouseholdRecord: Decodable, Equatable {
    static let storageKey = "sonos_known_households"

    let id: String
    let lastKnownIP: String
    /// Every speaker address seen for this household, so a single speaker going
    /// away or changing address does not strand the rest.
    let knownIPs: Set<String>
    let lastConnected: Date

    private enum CodingKeys: String, CodingKey {
        case id, lastKnownIP, knownIPs, lastConnected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        lastKnownIP = try container.decodeIfPresent(String.self, forKey: .lastKnownIP) ?? ""
        knownIPs = try container.decodeIfPresent(Set<String>.self, forKey: .knownIPs) ?? []
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected) ?? .distantPast
    }

    /// Addresses to try, most likely to answer first: `lastKnownIP` led most
    /// recently, then the rest of the household in a stable order.
    var candidateIPs: [String] {
        var ips = lastKnownIP.isEmpty ? [] : [lastKnownIP]
        ips.append(contentsOf: knownIPs.sorted().filter { $0 != lastKnownIP && !$0.isEmpty })
        return ips
    }

    /// Households as last synced from iCloud. The main app stores them as a JSON
    /// string (CloudStorage has no Codable overload), encoded with a default
    /// `JSONEncoder` — so the default `JSONDecoder` date strategy here matches.
    static func stored() -> [SonosHouseholdRecord] {
        guard let json = NSUbiquitousKeyValueStore.default.string(forKey: storageKey),
              !json.isEmpty,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SonosHouseholdRecord].self, from: data)) ?? []
    }

    /// The household Cue Mini should follow: the one the user pinned, else the
    /// most recently connected. Mirrors `activeHousehold` in the main app, including
    /// the fallback when a pin refers to a household that has since been removed.
    static func active(preferring preferredID: String?) -> SonosHouseholdRecord? {
        let households = stored()
        if let preferredID, !preferredID.isEmpty,
           let pinned = households.first(where: { $0.id == preferredID }) {
            return pinned
        }
        return households.max(by: { $0.lastConnected < $1.lastConnected })
    }
}
