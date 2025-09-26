import Foundation

public struct PlaybackStatus: Codable {
    public let queueId: String
    public let isDucking: Bool
    public let itemId: String
    public let previousItemId: String?
    public let playModes: PlayModes
    public let playbackState: String
    public let availablePlaybackActions: PlaybackActions
    public let positionMillis: Int
    public let objectType: String
    public let queueVersion: String
    public let previousPositionMillis: Int

    enum CodingKeys: String, CodingKey {
        case queueId, isDucking, itemId, previousItemId, playModes, playbackState, availablePlaybackActions, positionMillis, queueVersion, previousPositionMillis
        case objectType = "_objectType"
    }
}

public struct PlayModes: Codable {
    public let repeatMode: Bool
    public let shuffle: Bool
    public let crossfade: Bool
    public let repeatOne: Bool
    public let objectType: String

    enum CodingKeys: String, CodingKey {
        case shuffle, crossfade, repeatOne
        case repeatMode = "repeat"
        case objectType = "_objectType"
    }
}

public struct PlaybackActions: Codable {
    public let canRepeatOne: Bool
    public let canCrossfade: Bool
    public let objectType: String
    public let canStop: Bool
    public let canSkipToPrevious: Bool
    public let canShuffle: Bool
    public let canPause: Bool
    public let canRepeat: Bool
    public let canSkipBack: Bool
    public let canSeek: Bool
    public let canPlay: Bool
    public let canSkip: Bool

    enum CodingKeys: String, CodingKey {
        case canRepeatOne, canCrossfade, canStop, canSkipToPrevious, canShuffle, canPause, canRepeat, canSkipBack, canSeek, canPlay, canSkip
        case objectType = "_objectType"
    }
}

public struct PlaybackEvent {
    public let info: SocketInfo
    public let playbackState: PlaybackStatus?

    // Decode from the array format
    static func decode(from data: Data) throws -> Self? {
        // Decode as an array of generic JSON objects
        let decoder = JSONDecoder()
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        var info: SocketInfo?
        var state: PlaybackStatus?

        for item in array {
            // Try decoding info
            if info == nil, let infoData = try? JSONSerialization.data(withJSONObject: item),
               let i = try? decoder.decode(SocketInfo.self, from: infoData) {
                info = i
                if info?.type != "playbackStatus" { return nil }
                continue
            }
            do {
                guard let stateData = try? JSONSerialization.data(withJSONObject: item) else { continue }
                let s = try decoder.decode(PlaybackStatus.self, from: stateData)
            } catch {
                print(error)
            }

            // Try decoding state
            if state == nil, let stateData = try? JSONSerialization.data(withJSONObject: item),
               let s = try? decoder.decode(PlaybackStatus.self, from: stateData),
               s.objectType != "" {
                state = s
                continue
            }
        }

        guard let socketInfo = info else {
            throw NSError(domain: "PlaybackEvent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing SocketInfo"])
        }

        return Self(info: socketInfo, playbackState: state)
    }
}
