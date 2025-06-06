import Foundation

/// Represents audio quality information for a track
public struct AudioQuality: Codable, Equatable {
    /// The bit depth of the audio (e.g., 16, 24)
    public let bitDepth: Int?
    /// The sample rate in Hz (e.g., 44100, 48000)
    public let sampleRate: Int?
    /// Whether the audio is lossless
    public let lossless: Bool?
    /// Whether the audio is immersive (e.g., spatial audio)
    public let immersive: Bool?
    
    /// The object type from the Sonos API
    let _objectType: String?
    
    public var sampleRateFormatted: String {
        guard let sampleRate = sampleRate else { return "" }
        let rateInKHz = Double(sampleRate) / 1000.0
        if rateInKHz.truncatingRemainder(dividingBy: 1) == 0 {
            // No decimal point needed
            return "\(Int(rateInKHz)) kHz"
        } else {
            // Keep 1 decimal place if needed (e.g. 44.1 kHz)
            return String(format: "%.1f kHz", rateInKHz)
        }
    }
}
