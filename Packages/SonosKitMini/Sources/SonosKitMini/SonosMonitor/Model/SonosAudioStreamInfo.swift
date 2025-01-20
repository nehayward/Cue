// Audio stream information model
public struct SonosAudioStreamInfo: Hashable, Equatable {
    public let bitDepth: Int       // bd: bit depth
    public let sampleRate: Int     // sr: sample rate
    public let channels: Int       // c: number of channels
    public let lossless: Bool      // l: lossless flag
    public let dolbyEncoded: Bool  // d: dolby flag
    public var info: SonosAudioInputFormat?
    
    var description: String {
        let format = channels == 6 ? "5.1" : "\(channels).0"
        let quality = lossless ? "Lossless" : "Lossy"
        let dolby = dolbyEncoded ? "Dolby" : ""
        return "\(bitDepth)bit/\(sampleRate/1000)kHz \(format) \(quality) \(dolby)".trimmingCharacters(in: .whitespaces)
    }
    
    static func parse(from streamInfo: String) -> Self? {
        var bitDepth = 0
        var sampleRate = 0
        var channels = 0
        var lossless = false
        var dolbyEncoded = false
        
        let components = streamInfo.components(separatedBy: ",")
        for component in components {
            let parts = component.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
            guard parts.count == 2 else { continue }
            
            let value = Int(parts[1]) ?? 0
            switch parts[0] {
            case "bd": bitDepth = value
            case "sr": sampleRate = value
            case "c": channels = value
            case "l": lossless = value == 1
            case "d": dolbyEncoded = value == 1
            default: break
            }
        }
        
        print(streamInfo)
        
        if !streamInfo.isEmpty && streamInfo.range(of: "[^0-9]", options: .regularExpression) == nil, let audioInput = Int(streamInfo) {
            return Self(bitDepth: 0, sampleRate: 0, channels: 0, lossless: false, dolbyEncoded: false, info: SonosAudioInputFormat(rawValue: audioInput))
        }

        
        return Self(
            bitDepth: bitDepth,
            sampleRate: sampleRate,
            channels: channels,
            lossless: lossless,
            dolbyEncoded: dolbyEncoded
        )
    }
}
