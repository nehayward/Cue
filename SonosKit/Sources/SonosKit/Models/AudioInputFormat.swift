
public enum AudioInputFormat: Int {
    case noInputConnected = 0
    case stereo = 2
    case dolbyStereo = 7
    case dolbySurround = 18
    case noInput = 21
    case noAudio = 22
    case dolbyAtmosDDPlus = 59
    case dolbyAtmosTrueHD = 61
    case dolbyAtmosMAT = 63
    case PCM = 33554434
    case PCMNoAudio = 33554454
    case dolbyDigital = 33554488
    case dolbyDigitalPlusStereo = 33554490
    case dolbyTrueHD = 33554492
    case dolbyMultiChannelPCM = 33554494
    case multiChannelPCM = 84934658
    case dolbySurroundAudio = 84934713
    case dolbyDigitalPlus = 84934714
    case dolbyMultiChannel = 84934718
    case DTS = 84934721
    case unknown = -1

    public var description: String {
        switch self {
        case .unknown:
            "--"
        case .noInputConnected:
            "No input connected"
        case .stereo:
            "Stereo"
        case .dolbyStereo:
            "Dolby 2.0"
        case .dolbySurround, .dolbySurroundAudio:
            "Dolby 5.1"
        case .noInput:
            "No input"
        case .noAudio:
            "No audio"
        case .dolbyAtmosDDPlus:
            "Dolby Atmos (DD+)"
        case .dolbyAtmosTrueHD:
            "Dolby Atmos (TrueHD)"
        case .dolbyAtmosMAT:
            "Dolby Atmos (MAT 2.0)"
        case .PCM:
            "PCM 2.0"
        case .PCMNoAudio:
            "PCM 2.0 no audio"
        case .dolbyDigital:
            "Dolby 2.0"
        case .dolbyDigitalPlusStereo:
            "Dolby Digital Plus 2.0"
        case .dolbyTrueHD:
            "Dolby TrueHD 2.0"
        case .dolbyMultiChannelPCM:
            "Dolby Multichannel PCM 2.0"
        case .multiChannelPCM:
            "Multichannel PCM 5.1"
        case .dolbyDigitalPlus:
            "Dolby Digital Plus 5.1"
        case .dolbyMultiChannel:
            "Dolby Multichannel PCM 5.1"
        case .DTS:
            "DTS 5.1"
        }
    }
}
