import Foundation

public enum SonosServiceError: Error {
    case noWifi
    case sonosSystemNotFound
    case permissionDenied
    case cancelled
    case parseError(String)
    case timeout
    case serviceUnavailable
    case cantPlayContent(upnpCode: String?)
}

extension SonosServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noWifi: "Connect to Wi-Fi to play on Sonos."
        case .sonosSystemNotFound: "Couldn't reach your Sonos system. Make sure your speakers are on the same network."
        case .permissionDenied: "Clic needs Local Network access to talk to Sonos. Enable it in Settings."
        case .timeout: "Timed out talking to your Sonos system. Try again."
        case .serviceUnavailable: "Your Sonos speaker isn't responding right now. Try again in a moment."
        case .cancelled: "Playback was cancelled."
        case .parseError: "Sonos returned an unexpected response. Try again."
        case .cantPlayContent(let code):
            switch code {
            case "402", "712": "Sonos couldn't read this track's metadata. The file may be tagged with characters Sonos can't parse."
            case "714": "Sonos doesn't support this file format."
            case "716": "Sonos couldn't find this track. It may have moved or been removed from your library."
            case "718": "Sonos couldn't play this on the selected speaker. Try a different room."
            case "800": "Sonos isn't signed in to this music service. Add or reconnect the service in the Sonos app, then try again."
            default: "Sonos couldn't play this track."
            }
        }
    }
}
